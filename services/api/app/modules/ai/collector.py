"""Context collector: turns stored telemetry into evidence (AI_ARCHITECTURE.md §1-2).

Everything here is deterministic. All queries are scoped by `org_id` (tenant isolation
applies to the AI exactly as it does to the API). Missing data is reported as a data gap
rather than silently omitted.
"""

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from statistics import fmean
from typing import Any
from uuid import UUID

from sqlalchemy import and_, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.ai.evidence import EvidenceRegistry, Redactor, fmt_num, fmt_time
from app.modules.ai.models import EvidenceKind
from app.modules.alerts.models import AlertInstance, AlertRule
from app.modules.deployments.models import Deployment
from app.modules.incidents.models import Incident, IncidentDeployment, IncidentStatus
from app.modules.services.models import Service
from app.modules.telemetry.metrics import ERROR_RATE, Agg, query_series
from app.modules.telemetry.models import log_events, metric_rollups_1m

BASELINE = timedelta(minutes=60)
# Alerts fire after their evaluation window and `for` duration, so the underlying change
# usually starts several minutes before the incident; keep that out of the baseline.
LEAD = timedelta(minutes=15)
MAX_WINDOW = timedelta(hours=2)
DEPLOY_LOOKBACK = timedelta(hours=24)
LOG_HISTORY = timedelta(hours=6)
SIMILAR_LOOKBACK = timedelta(days=90)
MAX_METRICS = 8
MAX_LOG_GROUPS = 5
MAX_DEPLOYS = 5
MAX_SIMILAR = 3
MAX_SERIES_POINTS = 40
LOG_LEVELS = ("warn", "error", "fatal")

# How each standard metric is best summarised (docs/DATABASE_SCHEMA.md).
_METRIC_AGG: dict[str, Agg] = {
    "http.server.duration_ms": "p95",
    "http.server.requests": "sum",
    "process.cpu.utilization": "avg",
    "process.memory.usage_bytes": "avg",
    "db.pool.connections_in_use": "max",
}
_SKIP = {"http.server.errors"}  # represented by the derived error rate


@dataclass
class Window:
    baseline_start: datetime
    start: datetime  # incident window start (includes the lead)
    end: datetime


@dataclass
class Collected:
    registry: EvidenceRegistry
    data_gaps: list[str] = field(default_factory=list)
    service: Service | None = None
    window: Window | None = None


def incident_window(inc: Incident, now: datetime) -> Window:
    end_cap = inc.resolved_at if inc.status == IncidentStatus.RESOLVED and inc.resolved_at else now
    end = min(end_cap, inc.started_at + MAX_WINDOW, now)
    start = inc.started_at - LEAD
    end = max(end, inc.started_at + timedelta(minutes=1))
    return Window(baseline_start=start - BASELINE, start=start, end=end)


def _minute(t: datetime) -> datetime:
    return t.replace(second=0, microsecond=0)


def _change_pct(before: float | None, after: float | None) -> float | None:
    if before is None or after is None or before == 0:
        return None
    return round((after - before) / abs(before) * 100, 1)


def _sample(points: Sequence[tuple[datetime, float | None]]) -> list[list[Any]]:
    pts = [(t, v) for t, v in points if v is not None]
    if len(pts) > MAX_SERIES_POINTS:
        step = len(pts) / MAX_SERIES_POINTS
        pts = [pts[int(i * step)] for i in range(MAX_SERIES_POINTS)]
    return [[t.strftime("%H:%M"), round(v, 4)] for t, v in pts]


# --------------------------------------------------------------------------- metrics


async def metric_names(
    session: AsyncSession, org_id: UUID, service_id: UUID, start: datetime, end: datetime
) -> list[str]:
    rows = await session.scalars(
        select(metric_rollups_1m.c.name)
        .where(
            metric_rollups_1m.c.org_id == org_id,
            metric_rollups_1m.c.service_id == service_id,
            metric_rollups_1m.c.bucket >= start,
            metric_rollups_1m.c.bucket < end,
        )
        .distinct()
    )
    return sorted(rows.all())


def default_agg(name: str) -> Agg:
    if name == ERROR_RATE:
        return "ratio"
    return _METRIC_AGG.get(name, "avg")


async def add_metric_evidence(
    session: AsyncSession,
    reg: EvidenceRegistry,
    *,
    org_id: UUID,
    service: Service,
    name: str,
    agg: Agg,
    start: datetime,
    end: datetime,
    baseline_start: datetime | None = None,
) -> bool:
    """Adds one metric item. With `baseline_start`, compares [baseline_start, start) with
    [start, end); otherwise summarises [start, end). Returns False when there is no data."""
    q_start = baseline_start or start
    points = await query_series(
        session,
        org_id=org_id,
        service_id=service.id,
        name=name,
        agg=agg,
        start=_minute(q_start),
        end=end,
        step_s=60,
    )
    window_pts = [(t, v) for t, v in points if t >= _minute(start) and v is not None]
    if not window_pts:
        return False
    label = "error rate" if agg == "ratio" else f"{agg} of {name}"
    peak_t, peak = max(window_pts, key=lambda p: p[1])
    mean = fmean(v for _, v in window_pts)
    excerpt: dict[str, Any] = {
        "service": service.slug,
        "metric": name,
        "aggregation": agg,
        "window": {"from": start.isoformat(), "to": end.isoformat()},
        "mean": round(mean, 4),
        "peak": round(peak, 4),
        "peak_at": peak_t.isoformat(),
        "minutes_with_data": len(window_pts),
        "series": _sample(window_pts),
    }
    if baseline_start is not None:
        base_pts = [v for t, v in points if t < _minute(start) and v is not None]
        baseline = fmean(base_pts) if base_pts else None
        excerpt["baseline"] = round(baseline, 4) if baseline is not None else None
        excerpt["change_pct_peak_vs_baseline"] = _change_pct(baseline, peak)
        changed_at = None
        if baseline is not None and baseline > 0:
            changed_at = next((t for t, v in window_pts if v > baseline * 1.5), None)
        excerpt["first_above_1_5x_baseline_at"] = changed_at.isoformat() if changed_at else None
        change = excerpt["change_pct_peak_vs_baseline"]
        excerpt["text"] = (
            f"{service.slug} {label}: baseline {fmt_num(baseline)} → peak {fmt_num(peak)} "
            f"at {fmt_time(peak_t)}" + (f" ({change:+.0f}%)" if change is not None else "")
        )
    else:
        excerpt["text"] = (
            f"{service.slug} {label} from {fmt_time(start)} to {fmt_time(end)}: "
            f"mean {fmt_num(mean)}, peak {fmt_num(peak)} at {fmt_time(peak_t)}"
        )
    reg.add(
        EvidenceKind.METRIC,
        f"{service.slug} · {label}",
        excerpt,
        {
            "type": "metric",
            "service_id": str(service.id),
            "name": name,
            "aggregation": agg,
            "from": q_start.isoformat(),
            "to": end.isoformat(),
            "step_s": 60,
        },
        observed_at=peak_t,
    )
    return True


# ------------------------------------------------------------------------------ logs


async def add_log_evidence(
    session: AsyncSession,
    reg: EvidenceRegistry,
    redact: Redactor,
    *,
    org_id: UUID,
    service: Service,
    start: datetime,
    end: datetime,
    levels: tuple[str, ...] = LOG_LEVELS,
    contains: str | None = None,
    limit: int = MAX_LOG_GROUPS,
) -> int:
    """Groups matching logs by fingerprint (most frequent first). Returns groups added."""
    le = log_events.c
    history_start = start - LOG_HISTORY
    conds = [
        le.org_id == org_id,
        le.service_id == service.id,
        le.ts >= history_start,
        le.ts < end,
        le.level.in_(levels),
    ]
    if contains:
        escaped = contains.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        conds.append(le.message.ilike(f"%{escaped}%", escape="\\"))
    in_window = le.ts >= start
    rows = (
        await session.execute(
            select(
                le.fingerprint,
                le.level,
                func.count().filter(in_window).label("n"),
                func.count().filter(~in_window).label("before"),
                func.min(le.ts).filter(in_window).label("first"),
                func.max(le.ts).filter(in_window).label("last"),
                # Same fingerprint = same normalised message; any one is a fair sample.
                func.max(le.message).filter(in_window).label("sample"),
            )
            .where(and_(*conds))
            .group_by(le.fingerprint, le.level)
            .having(func.count().filter(in_window) > 0)
            .order_by(text("n DESC"))
            .limit(limit)
        )
    ).all()
    for fp, level, n, before, first, last, sample in rows:
        message = redact(sample, limit=300) or ""
        novelty = (
            "new: not seen in the previous 6h"
            if before == 0
            else f"also seen {before}x in the previous 6h"
        )
        reg.add(
            EvidenceKind.LOG,
            f"{service.slug} · {n}x {level.upper()} log",
            {
                "service": service.slug,
                "level": level,
                "count": n,
                "first_seen": first.isoformat(),
                "last_seen": last.isoformat(),
                "seen_in_previous_6h": before,
                "sample_message": message,
                "text": f"{n}x {level.upper()} from {fmt_time(first)} to {fmt_time(last)} "
                f"({novelty}): “{message[:120]}”",
            },
            {
                "type": "logs",
                "service_id": str(service.id),
                "fingerprint": fp,
                "levels": list(levels),
                "contains": contains,
                "from": start.isoformat(),
                "to": end.isoformat(),
            },
            observed_at=first,
        )
    return len(rows)


async def any_logs(
    session: AsyncSession, org_id: UUID, service_id: UUID, start: datetime, end: datetime
) -> bool:
    le = log_events.c
    hit = await session.scalar(
        select(le.ts)
        .where(le.org_id == org_id, le.service_id == service_id, le.ts >= start, le.ts < end)
        .limit(1)
    )
    return hit is not None


# ----------------------------------------------------------------------- deployments


async def add_deployment_evidence(
    session: AsyncSession,
    reg: EvidenceRegistry,
    redact: Redactor,
    *,
    org_id: UUID,
    service: Service,
    start: datetime,
    end: datetime,
    incident: Incident | None = None,
    limit: int = MAX_DEPLOYS,
) -> int:
    stmt = (
        select(Deployment)
        .where(
            Deployment.org_id == org_id,
            Deployment.service_id == service.id,
            Deployment.started_at >= start,
            Deployment.started_at < end,
        )
        .order_by(Deployment.started_at.desc())
        .limit(limit)
    )
    deps = list((await session.scalars(stmt)).all())
    correlations: dict[UUID, tuple[str, float]] = {}
    if incident is not None and deps:
        rows = await session.execute(
            select(
                IncidentDeployment.deployment_id,
                IncidentDeployment.correlation,
                IncidentDeployment.score,
            ).where(
                IncidentDeployment.org_id == org_id,
                IncidentDeployment.incident_id == incident.id,
            )
        )
        correlations = {d: (c.value, s) for d, c, s in rows.all()}
    for d in deps:
        excerpt: dict[str, Any] = {
            "service": service.slug,
            "version": d.version,
            "environment": d.environment,
            "status": d.status.value,
            "started_at": d.started_at.isoformat(),
            "finished_at": d.finished_at.isoformat() if d.finished_at else None,
            "commit_sha": (d.commit_sha or "")[:12] or None,
            # Untrusted text (written by whoever pushed the commit).
            "commit_message": redact(d.commit_message, limit=200),
        }
        when = ""
        if incident is not None:
            minutes = round((incident.started_at - d.started_at).total_seconds() / 60, 1)
            excerpt["minutes_before_incident"] = minutes
            when = (
                f", {minutes:g} min before the incident"
                if minutes >= 0
                else f", {-minutes:g} min after the incident started"
            )
            if d.id in correlations:
                corr, score = correlations[d.id]
                excerpt["correlation"] = {"status": corr, "heuristic_score": round(score, 3)}
        excerpt["text"] = (
            f"{service.slug} {d.version} deployed ({d.status.value}) "
            f"at {fmt_time(d.started_at)}{when}"
        )
        reg.add(
            EvidenceKind.DEPLOYMENT,
            f"{service.slug} deploy {d.version}",
            excerpt,
            {"type": "deployment", "deployment_id": str(d.id)},
            observed_at=d.started_at,
        )
    return len(deps)


# ---------------------------------------------------------------------------- alerts


async def add_alert_evidence(session: AsyncSession, reg: EvidenceRegistry, inc: Incident) -> int:
    rows = (
        await session.execute(
            select(AlertInstance, AlertRule)
            .join(AlertRule, AlertRule.id == AlertInstance.rule_id)
            .where(AlertInstance.org_id == inc.org_id, AlertInstance.incident_id == inc.id)
            .order_by(AlertInstance.started_at)
        )
    ).all()
    for ai, rule in rows:
        reg.add(
            EvidenceKind.ALERT,
            f"alert · {rule.name}",
            {
                "rule": rule.name,
                "metric": rule.metric,
                "aggregation": rule.aggregation.value,
                "comparator": rule.comparator.value,
                "threshold": rule.threshold,
                "window_s": rule.window_s,
                "last_value": ai.last_value,
                "state": ai.state.value,
                "fired_at": ai.fired_at.isoformat() if ai.fired_at else None,
                "text": f"Alert '{rule.name}': {rule.aggregation.value}({rule.metric}) "
                f"{rule.comparator.value} {fmt_num(rule.threshold)}; last value "
                f"{fmt_num(ai.last_value)} ({ai.state.value})",
            },
            {"type": "alert_instance", "alert_instance_id": str(ai.id)},
            observed_at=ai.fired_at or ai.started_at,
        )
    return len(rows)


# ------------------------------------------------------------------------- incidents


async def add_similar_incidents(
    session: AsyncSession,
    reg: EvidenceRegistry,
    redact: Redactor,
    *,
    org_id: UUID,
    service: Service,
    exclude: UUID | None,
    before: datetime,
    limit: int = MAX_SIMILAR,
) -> int:
    stmt = (
        select(Incident)
        .where(
            Incident.org_id == org_id,
            Incident.service_id == service.id,
            Incident.started_at >= before - SIMILAR_LOOKBACK,
            Incident.started_at < before,
        )
        .order_by((Incident.status == IncidentStatus.RESOLVED).desc(), Incident.started_at.desc())
        .limit(limit)
    )
    if exclude is not None:
        stmt = stmt.where(Incident.id != exclude)
    incs = list((await session.scalars(stmt)).all())
    for i in incs:
        add_incident_evidence(reg, redact, i, service_slug=service.slug, similar=True)
    return len(incs)


def add_incident_evidence(
    reg: EvidenceRegistry,
    redact: Redactor,
    i: Incident,
    *,
    service_slug: str | None,
    similar: bool = False,
) -> None:
    confirmed = redact(i.root_cause_confirmed, limit=300)
    note = redact(i.resolution_note, limit=300)
    tail = (
        f"; confirmed root cause: {confirmed}"
        if confirmed
        else (f"; resolution: {note}" if note else "")
    )
    reg.add(
        EvidenceKind.INCIDENT,
        f"{'past ' if similar else ''}incident {i.key}",
        {
            "key": i.key,
            "title": redact(i.title, limit=200),
            "service": service_slug,
            "severity": i.severity.value,
            "status": i.status.value,
            "started_at": i.started_at.isoformat(),
            "resolved_at": i.resolved_at.isoformat() if i.resolved_at else None,
            "resolution_note": note,
            "root_cause_confirmed_by_human": confirmed,
            "text": f"{i.key} ({i.severity.value}, {i.status.value}) “{i.title[:80]}” "
            f"started {i.started_at:%Y-%m-%d %H:%M} UTC{tail}",
        },
        {"type": "incident", "incident_id": str(i.id)},
        observed_at=i.started_at,
    )


# -------------------------------------------------------------------------- pipeline


async def collect(
    session: AsyncSession, inc: Incident, redact: Redactor, *, now: datetime | None = None
) -> Collected:
    now = now or datetime.now(UTC)
    reg = EvidenceRegistry()
    out = Collected(registry=reg)
    await add_alert_evidence(session, reg, inc)

    service = (
        await session.scalar(
            select(Service).where(Service.org_id == inc.org_id, Service.id == inc.service_id)
        )
        if inc.service_id
        else None
    )
    if service is None:
        out.data_gaps.append(
            "The incident is not linked to a service, so no metrics, logs or deployments "
            "could be collected."
        )
        return out
    out.service = service
    w = incident_window(inc, now)
    out.window = w

    names = await metric_names(session, inc.org_id, service.id, w.baseline_start, w.end)
    specs: list[tuple[str, Agg]] = []
    if "http.server.requests" in names and "http.server.errors" in names:
        specs.append((ERROR_RATE, "ratio"))
    specs += [(n, default_agg(n)) for n in names if n not in _SKIP]
    added = 0
    for name, agg in specs[:MAX_METRICS]:
        added += await add_metric_evidence(
            session,
            reg,
            org_id=inc.org_id,
            service=service,
            name=name,
            agg=agg,
            start=w.start,
            end=w.end,
            baseline_start=w.baseline_start,
        )
    if added == 0:
        out.data_gaps.append(
            f"No metrics were ingested for {service.slug} between {fmt_time(w.baseline_start)} "
            f"and {fmt_time(w.end)}."
        )
    elif any(
        e.kind == EvidenceKind.METRIC and e.excerpt.get("baseline") is None for e in reg.items
    ):
        out.data_gaps.append(
            f"No baseline for some {service.slug} metrics: there is no data in the hour before "
            f"{fmt_time(w.start)}, so changes can't be compared with normal behaviour."
        )
    if added and len(specs) > MAX_METRICS:
        out.data_gaps.append(f"Only the first {MAX_METRICS} of {len(specs)} metrics were included.")

    groups = await add_log_evidence(
        session, reg, redact, org_id=inc.org_id, service=service, start=w.start, end=w.end
    )
    if groups == 0:
        if await any_logs(session, inc.org_id, service.id, w.start, w.end):
            out.data_gaps.append(
                f"No warning or error logs from {service.slug} in the incident window "
                "(info logs exist)."
            )
        else:
            out.data_gaps.append(
                f"No logs were ingested for {service.slug} in the incident window."
            )

    deps = await add_deployment_evidence(
        session,
        reg,
        redact,
        org_id=inc.org_id,
        service=service,
        start=inc.started_at - DEPLOY_LOOKBACK,
        end=inc.started_at + timedelta(minutes=5),
        incident=inc,
    )
    if deps == 0:
        out.data_gaps.append(
            f"No deployments of {service.slug} were recorded in the 24h before the incident "
            "(or deployment tracking is not connected)."
        )

    await add_similar_incidents(
        session,
        reg,
        redact,
        org_id=inc.org_id,
        service=service,
        exclude=inc.id,
        before=inc.started_at,
    )
    out.data_gaps.append(
        "Service dependencies are not modelled in DevPulse; upstream causes can only be "
        "inferred from this service's own logs and metrics."
    )
    return out

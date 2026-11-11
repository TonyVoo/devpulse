"""Alert evaluation engine (Celery beat, every 30s).

Per enabled rule: compute the aggregate of the rule's metric over its window from RAW
points (exact percentiles), then advance the instance state machine:

    (none) --breach--> pending --held for_s--> firing --clear--> resolved
                         └──clear──> resolved (silently, never opened an incident)

Firing opens an incident, or attaches to the still-open incident of the previous episode
of the same rule (dedup). Clearing a firing alert adds a timeline event but does NOT
resolve the incident: people resolve incidents.

Only one evaluator runs at a time (transaction-scoped advisory lock).
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.alerts.models import (
    Aggregation,
    AlertInstance,
    AlertRule,
    AlertState,
    Comparator,
    Severity,
)
from app.modules.alerts.schemas import ERROR_RATE
from app.modules.incidents.models import (
    ActorType,
    EventType,
    Incident,
    IncidentSource,
    IncidentStatus,
)
from app.modules.incidents.service import add_event, create_incident
from app.modules.services.models import Health, Service

log = structlog.get_logger(__name__)

EVAL_LOCK_ID = 7_201_001  # arbitrary, app-wide constant
NO_DATA_AFTER = timedelta(minutes=10)

_AGG_SQL = {
    Aggregation.AVG: "avg(value)",
    Aggregation.SUM: "sum(value)",
    Aggregation.MIN: "min(value)",
    Aggregation.MAX: "max(value)",
    Aggregation.P95: "percentile_cont(0.95) WITHIN GROUP (ORDER BY value)",
    Aggregation.P99: "percentile_cont(0.99) WITHIN GROUP (ORDER BY value)",
}


def breached(value: float, comparator: Comparator, threshold: float) -> bool:
    return {
        Comparator.GT: value > threshold,
        Comparator.GTE: value >= threshold,
        Comparator.LT: value < threshold,
        Comparator.LTE: value <= threshold,
    }[comparator]


async def compute_value(session: AsyncSession, rule: AlertRule, *, end: datetime) -> float | None:
    """Aggregate over [end - window, end). None means no data (not zero)."""
    params = {
        "org_id": rule.org_id,
        "service_id": rule.service_id,
        "start": end - timedelta(seconds=rule.window_s),
        "end": end,
    }
    if rule.aggregation == Aggregation.RATIO and rule.metric == ERROR_RATE:
        sql = """
            SELECT sum(value) FILTER (WHERE name = 'http.server.errors')
                   / NULLIF(sum(value) FILTER (WHERE name = 'http.server.requests'), 0)
            FROM metric_points
            WHERE org_id = :org_id AND service_id = :service_id
              AND name IN ('http.server.errors', 'http.server.requests')
              AND ts >= :start AND ts < :end
        """
    else:
        sql = f"""
            SELECT {_AGG_SQL[rule.aggregation]} FROM metric_points
            WHERE org_id = :org_id AND service_id = :service_id AND name = :name
              AND ts >= :start AND ts < :end
        """  # noqa: S608 - aggregation from a fixed whitelist
        params["name"] = rule.metric
    value = (await session.execute(text(sql), params)).scalar_one_or_none()
    return float(value) if value is not None else None


@dataclass
class EvalStats:
    rules: int = 0
    fired: int = 0
    resolved: int = 0
    incidents_opened: int = 0
    no_data: int = 0


async def evaluate_all(session: AsyncSession, *, now: datetime | None = None) -> EvalStats | None:
    """Returns None if another evaluator holds the lock."""
    now = now or datetime.now(UTC)
    got = (
        await session.execute(text("SELECT pg_try_advisory_xact_lock(:id)"), {"id": EVAL_LOCK_ID})
    ).scalar_one()
    if not got:
        await session.rollback()
        return None

    stats = EvalStats()
    rules = (
        await session.scalars(
            select(AlertRule)
            .join(Service, Service.id == AlertRule.service_id)
            .where(AlertRule.enabled.is_(True), Service.deleted_at.is_(None))
        )
    ).all()
    for rule in rules:
        stats.rules += 1
        await _evaluate_rule(session, rule, now, stats)
    await recompute_health(session, now=now)
    await session.commit()
    if stats.fired or stats.resolved:
        log.info("alerts_evaluated", **stats.__dict__)
    return stats


async def _evaluate_rule(
    session: AsyncSession, rule: AlertRule, now: datetime, stats: EvalStats
) -> None:
    value = await compute_value(session, rule, end=now)
    open_inst = await session.scalar(
        select(AlertInstance).where(
            AlertInstance.rule_id == rule.id, AlertInstance.state != AlertState.RESOLVED
        )
    )
    if value is None:
        # No data: keep the current state. Health reports "unknown" separately.
        stats.no_data += 1
        if open_inst is not None:
            open_inst.last_evaluated_at = now
        return

    is_breach = breached(value, rule.comparator, rule.threshold)
    if is_breach:
        if open_inst is None:
            open_inst = AlertInstance(
                org_id=rule.org_id,
                rule_id=rule.id,
                service_id=rule.service_id,
                state=AlertState.PENDING,
                started_at=now,
                last_value=value,
                last_evaluated_at=now,
            )
            session.add(open_inst)
            await session.flush()
        open_inst.last_value = value
        open_inst.last_evaluated_at = now
        if open_inst.state == AlertState.PENDING and now - open_inst.started_at >= timedelta(
            seconds=rule.for_s
        ):
            await _fire(session, rule, open_inst, value, now, stats)
        return

    if open_inst is not None:
        was_firing = open_inst.state == AlertState.FIRING
        open_inst.state = AlertState.RESOLVED
        open_inst.resolved_at = now
        open_inst.last_value = value
        open_inst.last_evaluated_at = now
        if was_firing:
            stats.resolved += 1
            inc = (
                await session.get(Incident, open_inst.incident_id)
                if open_inst.incident_id
                else None
            )
            if inc is not None:
                add_event(
                    session,
                    inc,
                    EventType.ALERT_RESOLVED,
                    actor_type=ActorType.SYSTEM,
                    data={"rule_id": str(rule.id), "rule": rule.name, "value": value},
                )
                inc.version += 1


async def _fire(
    session: AsyncSession,
    rule: AlertRule,
    inst: AlertInstance,
    value: float,
    now: datetime,
    stats: EvalStats,
) -> None:
    inst.state = AlertState.FIRING
    inst.fired_at = now
    stats.fired += 1
    detail = {
        "rule_id": str(rule.id),
        "rule": rule.name,
        "metric": rule.metric,
        "aggregation": rule.aggregation.value,
        "comparator": rule.comparator.value,
        "threshold": rule.threshold,
        "value": value,
        "window_s": rule.window_s,
    }

    # Dedup: attach to the open incident of this rule's previous episode, if any.
    previous = await session.scalar(
        select(Incident)
        .join(AlertInstance, AlertInstance.incident_id == Incident.id)
        .where(
            AlertInstance.rule_id == rule.id,
            AlertInstance.id != inst.id,
            Incident.status != IncidentStatus.RESOLVED,
        )
        .order_by(AlertInstance.started_at.desc())
        .limit(1)
    )
    if previous is not None:
        inst.incident_id = previous.id
        add_event(
            session, previous, EventType.ALERT_ATTACHED, actor_type=ActorType.SYSTEM, data=detail
        )
        previous.version += 1
        return

    svc = await session.get(Service, rule.service_id)
    title = f"{rule.name} on {svc.name if svc else 'service'}"
    inc = await create_incident(
        session,
        org_id=rule.org_id,
        title=title[:200],
        severity=rule.severity,
        source=IncidentSource.ALERT,
        service_id=rule.service_id,
        started_at=inst.started_at,
        summary=_describe(rule, value),
        is_demo=bool(svc and svc.is_demo),
        event_data=detail,
    )
    inst.incident_id = inc.id
    stats.incidents_opened += 1


def _describe(rule: AlertRule, value: float) -> str:
    op = {"gt": ">", "gte": "≥", "lt": "<", "lte": "≤"}[rule.comparator.value]
    window = f"{rule.window_s // 60} min" if rule.window_s >= 60 else f"{rule.window_s}s"
    if rule.aggregation == Aggregation.RATIO:
        return f"Error rate over {window} was {value:.1%} (threshold {op} {rule.threshold:.1%})."
    return (
        f"{rule.aggregation.value} of {rule.metric} over {window} was {value:.4g} "
        f"(threshold {op} {rule.threshold:g})."
    )


async def recompute_health(session: AsyncSession, *, now: datetime) -> int:
    """critical: a firing sev1/sev2 alert · degraded: any other firing alert ·
    healthy: data within 10 min and nothing firing · unknown: no recent data."""
    firing = (
        await session.execute(
            select(AlertInstance.service_id, func.min(AlertRule.severity))
            .join(AlertRule, AlertRule.id == AlertInstance.rule_id)
            .where(AlertInstance.state == AlertState.FIRING)
            .group_by(AlertInstance.service_id)
        )
    ).all()
    worst: dict[UUID, Severity] = {sid: sev for sid, sev in firing}
    changed = 0
    for svc in (await session.scalars(select(Service).where(Service.deleted_at.is_(None)))).all():
        sev = worst.get(svc.id)
        if sev in (Severity.SEV1, Severity.SEV2):
            health = Health.CRITICAL
        elif sev is not None:
            health = Health.DEGRADED
        elif svc.last_seen_at and now - svc.last_seen_at <= NO_DATA_AFTER:
            health = Health.HEALTHY
        else:
            health = Health.UNKNOWN
        if svc.health != health:
            svc.health = health
            svc.health_changed_at = now
            svc.version += 1
            changed += 1
    return changed

"""Golden scenarios (AI_ARCHITECTURE.md §8): incidents with a known, injected cause.

Used by the test suite (with the FakeProvider) and by `make ai-eval` (with a real
provider). All rows are written with `is_demo = true` into an org the caller owns; they are
synthetic evaluation data and never mixed into real telemetry.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.ids import uuid7
from app.modules.alerts.models import (
    Aggregation,
    AlertInstance,
    AlertRule,
    AlertState,
    Comparator,
    Severity,
)
from app.modules.deployments.models import BuildStatus, Deployment, DeploySource, DeployStatus
from app.modules.incidents.models import Incident, IncidentSource
from app.modules.incidents.service import create_incident
from app.modules.services.models import Service
from app.modules.telemetry.ingest import log_fingerprint
from app.modules.telemetry.models import log_events, metric_rollups_1m


@dataclass(frozen=True)
class Scenario:
    name: str
    description: str
    # The top-ranked cause should mention one of these (case-insensitive).
    expected_keywords: tuple[str, ...]
    build: Callable[[AsyncSession, UUID, datetime], Awaitable[Incident]]


def _minutes(start: datetime, end: datetime) -> list[datetime]:
    t = start.replace(second=0, microsecond=0)
    out = []
    while t < end:
        out.append(t)
        t += timedelta(minutes=1)
    return out


async def _service(session: AsyncSession, org_id: UUID, slug: str) -> Service:
    svc = Service(org_id=org_id, slug=slug, name=slug, environment="production", is_demo=True)
    session.add(svc)
    await session.flush()
    return svc


async def _gauge(
    session: AsyncSession,
    svc: Service,
    name: str,
    t0: datetime,
    *,
    before: float,
    after: float,
    change_at: datetime,
) -> None:
    rows = []
    for m in _minutes(t0 - timedelta(minutes=80), t0 + timedelta(minutes=10)):
        v = after if m >= change_at else before
        v *= 1 + 0.02 * ((m.minute % 5) - 2)  # small deterministic wobble
        rows.append(
            {
                "org_id": svc.org_id,
                "service_id": svc.id,
                "name": name,
                "bucket": m,
                "count": 60,
                "sum": v * 60,
                "min": v * 0.5,
                "max": v * 1.2,
                "p50": v * 0.6,
                "p95": v,
                "p99": v * 1.3,
                "is_demo": True,
            }
        )
    await session.execute(insert(metric_rollups_1m), rows)


async def _traffic(
    session: AsyncSession,
    svc: Service,
    t0: datetime,
    *,
    error_before: float,
    error_after: float,
    change_at: datetime,
    rpm: int = 600,
) -> None:
    rows = []
    for m in _minutes(t0 - timedelta(minutes=80), t0 + timedelta(minutes=10)):
        rate = error_after if m >= change_at else error_before
        for name, value in (("http.server.requests", rpm), ("http.server.errors", rpm * rate)):
            rows.append(
                {
                    "org_id": svc.org_id,
                    "service_id": svc.id,
                    "name": name,
                    "bucket": m,
                    "count": 1,
                    "sum": value,
                    "min": value,
                    "max": value,
                    "p50": value,
                    "p95": value,
                    "p99": value,
                    "is_demo": True,
                }
            )
    await session.execute(insert(metric_rollups_1m), rows)


async def _logs(
    session: AsyncSession,
    svc: Service,
    level: str,
    message: str,
    *,
    start: datetime,
    end: datetime,
    per_minute: int = 5,
) -> None:
    fp = log_fingerprint(level, message)
    rows = [
        {
            "org_id": svc.org_id,
            "service_id": svc.id,
            "ts": m + timedelta(seconds=i * (60 // per_minute)),
            "level": level,
            "message": message,
            "attributes": {},
            "fingerprint": fp,
            "is_demo": True,
        }
        for m in _minutes(start, end)
        for i in range(per_minute)
    ]
    await session.execute(insert(log_events), rows)


async def _deploy(
    session: AsyncSession, svc: Service, version: str, at: datetime, msg: str
) -> None:
    session.add(
        Deployment(
            org_id=svc.org_id,
            service_id=svc.id,
            environment="production",
            version=version,
            commit_sha="9f2c1e7d4b3a",
            commit_message=msg,
            status=DeployStatus.SUCCEEDED,
            build_status=BuildStatus.SUCCEEDED,
            started_at=at,
            finished_at=at + timedelta(minutes=2),
            source=DeploySource.API,
            external_id=f"eval-{uuid7()}",
            is_demo=True,
        )
    )
    await session.flush()


async def _incident(
    session: AsyncSession, svc: Service, title: str, t0: datetime, sev: Severity = Severity.SEV2
) -> Incident:
    return await create_incident(
        session,
        org_id=svc.org_id,
        title=title,
        severity=sev,
        source=IncidentSource.ALERT,
        service_id=svc.id,
        started_at=t0,
        is_demo=True,
    )


# ------------------------------------------------------------------------- scenarios


async def bad_deploy(session: AsyncSession, org_id: UUID, t0: datetime) -> Incident:
    svc = await _service(session, org_id, "checkout-api")
    change = t0 - timedelta(minutes=8)
    await _deploy(session, svc, "v2.14.0", t0 - timedelta(minutes=12), "Refactor cart serializer")
    await _gauge(
        session, svc, "http.server.duration_ms", t0, before=180, after=1400, change_at=change
    )
    await _traffic(session, svc, t0, error_before=0.004, error_after=0.06, change_at=change)
    await _logs(
        session,
        svc,
        "error",
        "TypeError: cannot read property 'lineItems' of undefined in CartSerializer.render",
        start=change,
        end=t0 + timedelta(minutes=5),
    )
    return await _incident(session, svc, "Checkout latency and errors elevated", t0)


async def pool_exhaustion(session: AsyncSession, org_id: UUID, t0: datetime) -> Incident:
    svc = await _service(session, org_id, "orders-api")
    change = t0 - timedelta(minutes=6)
    await _gauge(
        session, svc, "db.pool.connections_in_use", t0, before=18, after=50, change_at=change
    )
    await _gauge(
        session, svc, "http.server.duration_ms", t0, before=120, after=2600, change_at=change
    )
    await _traffic(session, svc, t0, error_before=0.002, error_after=0.03, change_at=change)
    await _logs(
        session,
        svc,
        "error",
        "connection pool exhausted: timed out acquiring connection after 30000ms (max=50)",
        start=change,
        end=t0 + timedelta(minutes=5),
    )
    return await _incident(session, svc, "Orders API slow", t0)


async def upstream_outage(session: AsyncSession, org_id: UUID, t0: datetime) -> Incident:
    svc = await _service(session, org_id, "payments-gateway")
    change = t0 - timedelta(minutes=4)
    await _gauge(
        session, svc, "http.server.duration_ms", t0, before=240, after=420, change_at=change
    )
    await _traffic(session, svc, t0, error_before=0.003, error_after=0.22, change_at=change)
    await _logs(
        session,
        svc,
        "error",
        "upstream card-processor returned 503 Service Unavailable",
        start=change,
        end=t0 + timedelta(minutes=5),
        per_minute=20,
    )
    return await _incident(session, svc, "Payment failures", t0, Severity.SEV1)


async def noisy_alert(session: AsyncSession, org_id: UUID, t0: datetime) -> Incident:
    svc = await _service(session, org_id, "search-api")
    await _gauge(session, svc, "http.server.duration_ms", t0, before=300, after=310, change_at=t0)
    await _traffic(session, svc, t0, error_before=0.001, error_after=0.001, change_at=t0)
    rule = AlertRule(
        org_id=org_id,
        service_id=svc.id,
        name="search p95 > 290ms",
        metric="http.server.duration_ms",
        aggregation=Aggregation.P95,
        comparator=Comparator.GT,
        threshold=290,
        window_s=300,
        for_s=0,
        severity=Severity.SEV3,
    )
    session.add(rule)
    await session.flush()
    inc = await _incident(session, svc, "search p95 > 290ms", t0, Severity.SEV3)
    session.add(
        AlertInstance(
            org_id=org_id,
            rule_id=rule.id,
            service_id=svc.id,
            state=AlertState.FIRING,
            started_at=t0,
            fired_at=t0,
            last_value=305,
            last_evaluated_at=t0,
            incident_id=inc.id,
        )
    )
    await session.flush()
    return inc


SCENARIOS = [
    Scenario(
        "bad_deploy",
        "A release 12 minutes before the incident introduced a serializer bug.",
        ("v2.14.0", "deploy", "release"),
        bad_deploy,
    ),
    Scenario(
        "pool_exhaustion",
        "The database connection pool hit its maximum; no recent deployment.",
        ("pool", "connection"),
        pool_exhaustion,
    ),
    Scenario(
        "upstream_outage",
        "An upstream card processor returns 503s.",
        ("upstream", "card-processor", "dependency"),
        upstream_outage,
    ),
    Scenario(
        "noisy_alert",
        "The alert threshold sits inside normal variation; nothing is actually wrong.",
        ("noisy", "threshold", "false"),
        noisy_alert,
    ),
]


def now() -> datetime:
    return datetime.now(UTC)

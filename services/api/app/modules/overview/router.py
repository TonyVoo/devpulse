"""Org overview: the mobile home screen and web dashboard header in one call."""

from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func, select, text

from app.core.deps import SessionDep
from app.core.tenancy import OrgContext, require_org
from app.modules.alerts.models import Severity
from app.modules.deployments.service import DeploymentOut, Deployments
from app.modules.incidents.models import Incident, IncidentStatus
from app.modules.incidents.schemas import IncidentOut
from app.modules.incidents.service import IncidentService
from app.modules.rbac.permissions import Permission
from app.modules.services.models import Health, Service

router = APIRouter(prefix="/orgs/{org_id}", tags=["overview"])

Window = Literal["1h", "24h", "7d"]
_WINDOWS: dict[str, tuple[timedelta, int]] = {
    # window → (span, bucket seconds for the request-volume series)
    "1h": (timedelta(hours=1), 60),
    "24h": (timedelta(hours=24), 1800),
    "7d": (timedelta(days=7), 6 * 3600),
}


class Totals(BaseModel):
    requests: float | None
    errors: float | None
    error_rate: float | None
    latency_avg_ms: float | None
    latency_p95_ms: float | None
    latency_p95_approximate: bool


class OverviewOut(BaseModel):
    window: Window
    generated_at: datetime
    services_total: int
    services_by_health: dict[Health, int]
    open_incidents_by_severity: dict[Severity, int]
    totals: Totals
    request_series: list[tuple[datetime, float | None]]
    recent_incidents: list[IncidentOut]
    recent_deployments: list[DeploymentOut]
    has_telemetry: bool


@router.get("/overview", response_model=OverviewOut)
async def overview(
    ctx: Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))],
    session: SessionDep,
    window: Annotated[Window, Query()] = "1h",
) -> OverviewOut:
    now = datetime.now(UTC)
    span, step = _WINDOWS[window]
    start = now - span

    health_rows = (
        await session.execute(
            select(Service.health, func.count())
            .where(Service.org_id == ctx.org_id, Service.deleted_at.is_(None))
            .group_by(Service.health)
        )
    ).all()
    by_health = {h: 0 for h in Health} | {h: n for h, n in health_rows}

    sev_rows = (
        await session.execute(
            select(Incident.severity, func.count())
            .where(Incident.org_id == ctx.org_id, Incident.status != IncidentStatus.RESOLVED)
            .group_by(Incident.severity)
        )
    ).all()
    by_sev = {s: 0 for s in Severity} | {s: n for s, n in sev_rows}

    params = {"org": ctx.org_id, "start": start, "end": now}
    t = (
        await session.execute(
            text("""
        SELECT
          sum(sum) FILTER (WHERE name = 'http.server.requests'),
          sum(sum) FILTER (WHERE name = 'http.server.errors'),
          sum(sum) FILTER (WHERE name = 'http.server.duration_ms')
            / NULLIF(sum(count) FILTER (WHERE name = 'http.server.duration_ms'), 0),
          sum(p95 * count) FILTER (WHERE name = 'http.server.duration_ms')
            / NULLIF(sum(count) FILTER (WHERE name = 'http.server.duration_ms'), 0)
        FROM metric_rollups_1m
        WHERE org_id = :org AND bucket >= :start AND bucket < :end
    """),
            params,
        )
    ).one()
    requests, errors, lat_avg, lat_p95 = (float(v) if v is not None else None for v in t)
    series = (
        await session.execute(
            text("""
        SELECT date_bin(:step, bucket, :start) AS b, sum(sum)
        FROM metric_rollups_1m
        WHERE org_id = :org AND name = 'http.server.requests' AND bucket >= :start AND bucket < :end
        GROUP BY b ORDER BY b
    """),
            # Series stop at the last complete minute (the current one is still filling up).
            {
                **params,
                "end": now.replace(second=0, microsecond=0),
                "step": timedelta(seconds=step),
            },
        )
    ).all()

    recent_incidents = (
        await IncidentService(session, ctx).page(
            limit=5, cursor=None, status=None, severity=None, service_id=None, assignee=None, q=None
        )
    ).items
    recent_deployments = (
        await Deployments(session, ctx).page(
            limit=5, cursor=None, service_id=None, status=None, since=None
        )
    ).items

    return OverviewOut(
        window=window,
        generated_at=now,
        services_total=sum(by_health.values()),
        services_by_health=by_health,
        open_incidents_by_severity=by_sev,
        totals=Totals(
            requests=requests,
            errors=errors,
            error_rate=(errors / requests) if requests and errors is not None else None,
            latency_avg_ms=lat_avg,
            latency_p95_ms=lat_p95,
            latency_p95_approximate=True,
        ),
        request_series=[(b, float(v) if v is not None else None) for b, v in series],
        recent_incidents=recent_incidents,
        recent_deployments=recent_deployments,
        has_telemetry=requests is not None,
    )

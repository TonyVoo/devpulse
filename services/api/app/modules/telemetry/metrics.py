"""Metric time-series queries over the 1-minute rollups."""

from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import SessionDep
from app.core.errors import Unprocessable
from app.core.tenancy import OrgContext, require_org
from app.modules.rbac.permissions import Permission
from app.modules.services.service import ServiceCatalog

router = APIRouter(prefix="/orgs/{org_id}/services/{service_id}", tags=["metrics"])

Agg = Literal["avg", "sum", "min", "max", "count", "p50", "p95", "p99", "ratio"]
ERROR_RATE = "http.server.error_rate"  # derived: errors / requests per bucket
MAX_POINTS = 500
MAX_RANGE = timedelta(days=7)
STEPS = (60, 300, 900, 1800, 3600, 6 * 3600, 86400)

# Percentiles across >1 minute are a count-weighted mean of per-minute percentiles: an
# approximation (true percentiles can't be merged). Documented in docs/API.md.
_AGG_SQL = {
    "avg": "sum(sum) / NULLIF(sum(count), 0)",
    "sum": "sum(sum)",
    "min": "min(min)",
    "max": "max(max)",
    "count": "sum(count)",
    "p50": "sum(p50 * count) / NULLIF(sum(count), 0)",
    "p95": "sum(p95 * count) / NULLIF(sum(count), 0)",
    "p99": "sum(p99 * count) / NULLIF(sum(count), 0)",
}


class SeriesOut(BaseModel):
    name: str
    aggregation: str
    points: list[tuple[datetime, float | None]]


class MetricsOut(BaseModel):
    from_: datetime
    to: datetime
    step_s: int
    approximate_percentiles: bool
    series: list[SeriesOut]


def choose_step(span: timedelta, requested: int | None) -> int:
    if requested is not None:
        if requested not in STEPS:
            raise Unprocessable(f"step must be one of {STEPS}", code="metrics.bad_step")
        if span.total_seconds() / requested > MAX_POINTS:
            raise Unprocessable(
                "Too many points; use a larger step", code="metrics.too_many_points"
            )
        return requested
    for step in STEPS:
        if span.total_seconds() / step <= MAX_POINTS / 2:
            return step
    return STEPS[-1]


def parse_spec(spec: str) -> tuple[str, Agg]:
    name, _, agg = spec.partition(":")
    agg = agg or ("ratio" if name == ERROR_RATE else "avg")
    if agg not in _AGG_SQL and agg != "ratio":
        raise Unprocessable(f"Unknown aggregation '{agg}'", code="metrics.bad_aggregation")
    if (agg == "ratio") != (name == ERROR_RATE):
        raise Unprocessable(f"'ratio' applies only to {ERROR_RATE}", code="metrics.bad_aggregation")
    return name, agg  # type: ignore[return-value]


async def query_series(
    session: AsyncSession,
    *,
    org_id: UUID,
    service_id: UUID,
    name: str,
    agg: Agg,
    start: datetime,
    end: datetime,
    step_s: int,
) -> list[tuple[datetime, float | None]]:
    params = {
        "org_id": org_id,
        "service_id": service_id,
        "start": start,
        "end": end,
        "step": timedelta(seconds=step_s),
    }
    if agg == "ratio":
        sql = """
            SELECT date_bin(:step, bucket, :start) AS b,
                   sum(sum) FILTER (WHERE name = 'http.server.errors')
                     / NULLIF(sum(sum) FILTER (WHERE name = 'http.server.requests'), 0)
            FROM metric_rollups_1m
            WHERE org_id = :org_id AND service_id = :service_id
              AND name IN ('http.server.errors', 'http.server.requests')
              AND bucket >= :start AND bucket < :end
            GROUP BY b ORDER BY b
        """
    else:
        sql = f"""
            SELECT date_bin(:step, bucket, :start) AS b, {_AGG_SQL[agg]}
            FROM metric_rollups_1m
            WHERE org_id = :org_id AND service_id = :service_id AND name = :name
              AND bucket >= :start AND bucket < :end
            GROUP BY b ORDER BY b
        """  # noqa: S608 - aggregation comes from a fixed whitelist
        params["name"] = name
    rows = await session.execute(text(sql), params)
    return [(b, float(v) if v is not None else None) for b, v in rows.all()]


@router.get("/metrics", response_model=MetricsOut)
async def get_metrics(
    service_id: UUID,
    ctx: Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))],
    session: SessionDep,
    names: Annotated[list[str], Query(min_length=1, max_length=8)],
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: datetime | None = None,
    step: int | None = None,
) -> MetricsOut:
    """`names=http.server.duration_ms:p95&names=http.server.error_rate`. Missing buckets
    mean no data (rendered as gaps, never as zero)."""
    await ServiceCatalog(session, ctx).get(service_id)
    # The current minute is still filling up; including it makes counters look like they
    # drop at the right edge. Series end at the last complete minute.
    last_complete = datetime.now(UTC).replace(second=0, microsecond=0)
    end = min((to or last_complete).astimezone(UTC), last_complete)
    start = (from_ or end - timedelta(hours=1)).astimezone(UTC)
    if start >= end or end - start > MAX_RANGE:
        raise Unprocessable("Range must be positive and at most 7 days", code="metrics.bad_range")
    step_s = choose_step(end - start, step)
    series = []
    for spec in names:
        name, agg = parse_spec(spec)
        points = await query_series(
            session,
            org_id=ctx.org_id,
            service_id=service_id,
            name=name,
            agg=agg,
            start=start,
            end=end,
            step_s=step_s,
        )
        series.append(SeriesOut(name=name, aggregation=agg, points=points))
    return MetricsOut(
        from_=start,
        to=end,
        step_s=step_s,
        approximate_percentiles=step_s > 60,
        series=series,
    )

"""Telemetry ingestion: validation, service resolution, bulk insert, rollup scheduling."""

import hashlib
import json
import re
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field, StringConstraints, field_validator
from sqlalchemy import insert, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.deps import SessionDep
from app.core.errors import Forbidden, Unprocessable
from app.core.redis import get_redis
from app.modules.services.models import Service, Tier
from app.modules.services.schemas import Environment, ServiceSlug
from app.modules.services.service import find_by_slug
from app.modules.telemetry.ingest_auth import IngestPrincipal, require_ingest_key
from app.modules.telemetry.models import log_events

router = APIRouter(prefix="/ingest/v1", tags=["ingest"])

MetricName = Annotated[
    str, StringConstraints(min_length=1, max_length=120, pattern=r"^[a-zA-Z][a-zA-Z0-9_.]*$")
]
DIRTY_SET = "rollup:dirty"


def _labels(v: dict[str, str]) -> dict[str, str]:
    if len(v) > 20:
        raise ValueError("at most 20 labels")
    for k, val in v.items():
        if len(k) > 64 or len(str(val)) > 256:
            raise ValueError("label keys ≤ 64 chars, values ≤ 256 chars")
    return v


class MetricPointIn(BaseModel):
    name: MetricName
    ts: datetime
    value: float = Field(allow_inf_nan=False)
    labels: dict[str, str] = Field(default_factory=dict)

    _check_labels = field_validator("labels")(_labels)


class MetricsIn(BaseModel):
    service: ServiceSlug
    environment: Environment = "production"
    points: list[MetricPointIn] = Field(min_length=1)


class LogIn(BaseModel):
    ts: datetime
    level: Literal["debug", "info", "warn", "warning", "error", "fatal"]
    message: Annotated[str, StringConstraints(min_length=1, max_length=8192)]
    attributes: dict[str, Any] = Field(default_factory=dict, max_length=30)
    trace_id: Annotated[str, StringConstraints(max_length=64)] | None = None


class LogsIn(BaseModel):
    service: ServiceSlug
    environment: Environment = "production"
    logs: list[LogIn] = Field(min_length=1, max_length=500)


class IngestAccepted(BaseModel):
    accepted: int
    service_id: UUID


def _check_timestamps(timestamps: list[datetime]) -> None:
    s = get_settings()
    now = datetime.now(UTC)
    earliest, latest = (
        now - timedelta(seconds=s.ingest_max_past_s),
        now + timedelta(seconds=s.ingest_max_future_s),
    )
    for ts in timestamps:
        if ts.tzinfo is None:
            raise Unprocessable("Timestamps must include a timezone", code="ingest.naive_timestamp")
        if not earliest <= ts <= latest:
            raise Unprocessable(
                "Timestamps must be within the last hour and at most 5 minutes ahead",
                code="ingest.timestamp_out_of_range",
            )


async def resolve_service(
    session: AsyncSession, principal: IngestPrincipal, slug: str, environment: str
) -> Service:
    svc = await find_by_slug(session, principal.org_id, slug, environment)
    if principal.service_id is not None and (svc is None or svc.id != principal.service_id):
        raise Forbidden(
            "This ingest key is bound to a different service", code="ingest.wrong_service"
        )
    if svc is None:
        if "services:autocreate" not in principal.scopes:
            raise Unprocessable(
                f"Unknown service '{slug}' in '{environment}'. Create it first or use a key "
                "with the services:autocreate scope.",
                code="ingest.unknown_service",
            )
        svc = Service(
            org_id=principal.org_id,
            slug=slug,
            name=slug,
            environment=environment,
            tier=Tier.HIGH,
            is_demo=principal.is_demo,
        )
        session.add(svc)
        await session.flush()
    return svc


async def _touch_service(session: AsyncSession, svc: Service, latest: datetime) -> None:
    if svc.last_seen_at is None or latest > svc.last_seen_at + timedelta(seconds=30):
        await session.execute(
            update(Service).where(Service.id == svc.id).values(last_seen_at=latest)
        )


_INSERT_POINTS = text(
    """
    INSERT INTO metric_points (org_id, service_id, name, ts, value, labels, is_demo)
    SELECT :org_id, :service_id, u.name, u.ts, u.value, u.labels::jsonb, :is_demo
    FROM unnest(
        CAST(:names AS text[]), CAST(:ts AS timestamptz[]),
        CAST(:values AS double precision[]), CAST(:labels AS text[])
    ) AS u(name, ts, value, labels)
    """
)


@router.post("/metrics", response_model=IngestAccepted, status_code=status.HTTP_202_ACCEPTED)
async def ingest_metrics(
    body: MetricsIn,
    session: SessionDep,
    principal: Annotated[IngestPrincipal, Depends(require_ingest_key("metrics:write"))],
) -> IngestAccepted:
    if len(body.points) > get_settings().ingest_max_points:
        raise Unprocessable("Too many points in one request", code="ingest.too_many_points")
    _check_timestamps([p.ts for p in body.points])
    svc = await resolve_service(session, principal, body.service, body.environment)
    # One statement for the whole batch (arrays + unnest) instead of a row-by-row
    # executemany: ~3x faster in the Phase 6 load test. COPY would be faster still, but
    # Postgres doesn't allow COPY FROM into tables with row-level security.
    await session.execute(
        _INSERT_POINTS,
        {
            "org_id": principal.org_id,
            "service_id": svc.id,
            "is_demo": principal.is_demo,
            "names": [p.name for p in body.points],
            "ts": [p.ts for p in body.points],
            "values": [p.value for p in body.points],
            "labels": [json.dumps(p.labels) for p in body.points],
        },
    )
    rows = body.points
    await _touch_service(session, svc, max(p.ts for p in body.points))
    await session.commit()

    # Mark touched minutes for the rollup worker (late points re-aggregate their minute).
    minutes = {p.ts.astimezone(UTC).replace(second=0, microsecond=0) for p in body.points}
    await get_redis().sadd(
        DIRTY_SET, *[f"{principal.org_id}|{svc.id}|{m.isoformat()}" for m in minutes]
    )
    return IngestAccepted(accepted=len(rows), service_id=svc.id)


# No word boundaries: numbers glued to units ("3012ms", "v2") must normalise too.
_NUMBERS = re.compile(
    r"0x[0-9a-f]+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\d+", re.IGNORECASE
)


def log_fingerprint(level: str, message: str) -> str:
    """Groups log lines that differ only by ids/numbers ("timeout after 3012ms" ≈ "…5004ms")."""
    normalized = _NUMBERS.sub("#", message.strip().splitlines()[0][:300].lower())
    return hashlib.sha256(f"{level}|{normalized}".encode()).hexdigest()[:32]


@router.post("/logs", response_model=IngestAccepted, status_code=status.HTTP_202_ACCEPTED)
async def ingest_logs(
    body: LogsIn,
    session: SessionDep,
    principal: Annotated[IngestPrincipal, Depends(require_ingest_key("logs:write"))],
) -> IngestAccepted:
    _check_timestamps([log.ts for log in body.logs])
    svc = await resolve_service(session, principal, body.service, body.environment)
    rows = []
    for log in body.logs:
        level = "warn" if log.level == "warning" else log.level
        rows.append(
            {
                "org_id": principal.org_id,
                "service_id": svc.id,
                "ts": log.ts,
                "level": level,
                "message": log.message,
                "attributes": log.attributes,
                "trace_id": log.trace_id,
                "fingerprint": log_fingerprint(level, log.message),
                "is_demo": principal.is_demo,
            }
        )
    await session.execute(insert(log_events), rows)
    await _touch_service(session, svc, max(log.ts for log in body.logs))
    await session.commit()
    return IngestAccepted(accepted=len(rows), service_id=svc.id)

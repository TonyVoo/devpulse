"""1-minute rollups and partition maintenance (run by Celery beat)."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from redis.asyncio import Redis
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.services.models import Service
from app.modules.telemetry.ingest import DIRTY_SET
from app.modules.telemetry.models import PARTITIONED_TABLES

log = structlog.get_logger(__name__)

RAW_RETENTION_DAYS = 7

_ROLLUP_SQL = text(
    """
    INSERT INTO metric_rollups_1m
        (org_id, service_id, name, bucket, count, sum, min, max, p50, p95, p99, is_demo)
    SELECT org_id, service_id, name, CAST(:bucket AS timestamptz),
           count(*), sum(value), min(value), max(value),
           percentile_cont(0.50) WITHIN GROUP (ORDER BY value),
           percentile_cont(0.95) WITHIN GROUP (ORDER BY value),
           percentile_cont(0.99) WITHIN GROUP (ORDER BY value),
           bool_or(is_demo)
    FROM metric_points
    WHERE org_id = :org_id AND service_id = :service_id
      AND ts >= CAST(:bucket AS timestamptz)
      AND ts < CAST(:bucket AS timestamptz) + interval '1 minute'
    GROUP BY org_id, service_id, name
    ON CONFLICT (org_id, service_id, name, bucket) DO UPDATE SET
        count = EXCLUDED.count, sum = EXCLUDED.sum, min = EXCLUDED.min, max = EXCLUDED.max,
        p50 = EXCLUDED.p50, p95 = EXCLUDED.p95, p99 = EXCLUDED.p99, is_demo = EXCLUDED.is_demo
    """
)


async def rollup_minute(
    session: AsyncSession, org_id: UUID, service_id: UUID, bucket: datetime
) -> None:
    await session.execute(
        _ROLLUP_SQL, {"org_id": org_id, "service_id": service_id, "bucket": bucket}
    )


async def process_dirty(session: AsyncSession, redis: Redis, *, batch: int = 2000) -> int:
    """Re-aggregate every (service, minute) touched by ingestion since the last run."""
    members: list[str] = await redis.spop(DIRTY_SET, batch) or []  # type: ignore[assignment]
    done = 0
    try:
        for member in members:
            org, svc, minute = member.split("|", 2)
            await rollup_minute(session, UUID(org), UUID(svc), datetime.fromisoformat(minute))
            done += 1
        await session.commit()
    except Exception:
        await session.rollback()
        if members:
            await redis.sadd(DIRTY_SET, *members)  # retry next run
        raise
    return done


async def sweep_recent(
    session: AsyncSession, *, now: datetime | None = None, minutes: int = 2
) -> int:
    """Safety net if a dirty marker was lost (e.g. Redis restart): re-roll the last few
    minutes for services that recently sent data."""
    now = now or datetime.now(UTC)
    current = now.replace(second=0, microsecond=0)
    rows = await session.execute(
        select(Service.org_id, Service.id).where(
            Service.last_seen_at >= now - timedelta(minutes=minutes + 1),
            Service.deleted_at.is_(None),
        )
    )
    n = 0
    for org_id, service_id in rows.all():
        for i in range(minutes + 1):
            await rollup_minute(session, org_id, service_id, current - timedelta(minutes=i))
            n += 1
    await session.commit()
    return n


async def maintain_partitions(
    session: AsyncSession, *, now: datetime | None = None
) -> dict[str, int]:
    """Create partitions a week ahead; drop daily partitions older than retention."""
    today = (now or datetime.now(UTC)).date()
    cutoff = today - timedelta(days=RAW_RETENTION_DAYS)
    created = dropped = 0
    for table in PARTITIONED_TABLES:
        created += int(
            (
                await session.execute(text(f"SELECT devpulse_ensure_partitions('{table}', 1, 7)"))
            ).scalar_one()
        )
        parts = await session.execute(
            text(
                "SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid "
                "WHERE i.inhparent = CAST(:t AS regclass)"
            ),
            {"t": table},
        )
        for (name,) in parts.all():
            suffix = name.rsplit("_p", 1)[-1]
            if suffix.isdigit() and datetime.strptime(suffix, "%Y%m%d").date() < cutoff:
                await session.execute(text(f'ALTER TABLE {table} DETACH PARTITION "{name}"'))
                await session.execute(text(f'DROP TABLE "{name}"'))
                dropped += 1
    await session.execute(
        text("DELETE FROM metric_rollups_1m WHERE bucket < now() - interval '90 days'")
    )
    await session.commit()
    log.info("partitions_maintained", created=created, dropped=dropped)
    return {"created": created, "dropped": dropped}

import asyncio
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import structlog
from redis.asyncio import Redis
from sqlalchemy import CursorResult, delete, or_
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings
from app.modules.alerts.evaluator import evaluate_all
from app.modules.auth.models import RefreshToken
from app.modules.incidents.idempotency import TTL as IDEMPOTENCY_TTL
from app.modules.incidents.models import IdempotencyKey
from app.modules.integrations.models import WebhookDelivery
from app.modules.telemetry.rollup import maintain_partitions, process_dirty, sweep_recent
from app.workers.celery_app import celery

log = structlog.get_logger(__name__)

# Keep spent tokens for a while so reuse of a stolen token is still detected.
RETENTION = timedelta(days=7)


async def _with_session[T](fn: Callable[[AsyncSession], Awaitable[T]]) -> T:
    """Fresh engine per task run: Celery workers have no long-lived event loop."""
    engine = create_async_engine(get_settings().database_url, pool_size=2)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            return await fn(session)
    finally:
        await engine.dispose()


def _rows(result: object) -> int:
    return int(result.rowcount or 0) if isinstance(result, CursorResult) else 0


def _run[T](fn: Callable[[AsyncSession], Awaitable[T]]) -> T:
    return asyncio.run(_with_session(fn))


async def purge_expired_refresh_tokens_async(database_url: str) -> int:
    engine = create_async_engine(database_url)
    try:
        cutoff = datetime.now(UTC) - RETENTION
        async with engine.begin() as conn:
            result = await conn.execute(
                delete(RefreshToken).where(
                    or_(RefreshToken.expires_at < cutoff, RefreshToken.revoked_at < cutoff)
                )
            )
        return int(result.rowcount or 0)
    finally:
        await engine.dispose()


@celery.task(name="auth.purge_expired_refresh_tokens")
def purge_expired_refresh_tokens() -> int:
    deleted = asyncio.run(purge_expired_refresh_tokens_async(get_settings().database_url))
    log.info("purged_refresh_tokens", deleted=deleted)
    return deleted


@celery.task(name="telemetry.rollup")
def rollup() -> dict[str, int]:
    async def go(session: AsyncSession) -> dict[str, int]:
        redis = Redis.from_url(get_settings().redis_url, decode_responses=True)
        try:
            dirty = await process_dirty(session, redis)
        finally:
            await redis.aclose()
        swept = await sweep_recent(session)
        return {"dirty": dirty, "swept": swept}

    return _run(go)


@celery.task(name="alerts.evaluate")
def evaluate_alerts() -> dict[str, Any] | None:
    stats = _run(evaluate_all)
    return stats.__dict__ if stats else None


@celery.task(name="telemetry.maintain_partitions")
def partitions() -> dict[str, int]:
    return _run(maintain_partitions)


@celery.task(name="maintenance.cleanup")
def cleanup() -> dict[str, int]:
    async def go(session: AsyncSession) -> dict[str, int]:
        now = datetime.now(UTC)
        idem = await session.execute(
            delete(IdempotencyKey).where(IdempotencyKey.created_at < now - IDEMPOTENCY_TTL)
        )
        hooks = await session.execute(
            delete(WebhookDelivery).where(WebhookDelivery.received_at < now - timedelta(days=30))
        )
        await session.commit()
        return {
            "idempotency_keys": _rows(idem),
            "webhook_deliveries": _rows(hooks),
        }

    return _run(go)

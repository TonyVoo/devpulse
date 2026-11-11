import asyncio
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import delete, or_
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import get_settings
from app.modules.auth.models import RefreshToken
from app.workers.celery_app import celery

log = structlog.get_logger(__name__)

# Keep spent tokens for a while so reuse of a stolen token is still detected.
RETENTION = timedelta(days=7)


async def purge_expired_refresh_tokens_async(database_url: str) -> int:
    # Fresh engine per run: Celery tasks run outside any long-lived event loop.
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

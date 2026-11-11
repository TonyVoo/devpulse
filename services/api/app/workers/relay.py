"""Outbox relay: publishes committed outbox rows to Redis (realtime) and dispatches pushes.

    python -m app.workers.relay

Woken immediately by `pg_notify('devpulse_outbox')` from the triggers, with a 2 s polling
fallback in case a notification is missed. Rows are claimed with FOR UPDATE SKIP LOCKED, so
several relays can run safely; each row is published at least once (clients treat events as
idempotent hints).
"""

import asyncio
import contextlib
import json
import signal
from datetime import UTC, datetime, timedelta

import asyncpg
import structlog
from redis.asyncio import Redis
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.logging import configure_logging
from app.core.redis import get_redis
from app.modules.notifications.push import (
    LoggingPushProvider,
    PushProvider,
    dispatch_incident_event,
)
from app.modules.realtime.gateway import channel
from app.modules.realtime.models import OutboxEvent

log = structlog.get_logger(__name__)
BATCH = 500
POLL_S = 2.0


async def relay_once(session: AsyncSession, redis: Redis, push: PushProvider) -> int:
    rows = list(
        (
            await session.scalars(
                select(OutboxEvent)
                .where(OutboxEvent.published_at.is_(None))
                .order_by(OutboxEvent.id)
                .limit(BATCH)
                .with_for_update(skip_locked=True)
            )
        ).all()
    )
    if not rows:
        await session.rollback()
        return 0
    for row in rows:
        if row.topic == "incident_event":
            # The payload's own "type" is the timeline event name; keep the envelope type.
            message = {**row.payload, "event": row.payload.get("type"), "type": "incident_event"}
            try:
                await dispatch_incident_event(session, push, row.org_id, row.payload)
            except Exception:
                log.exception("push_dispatch_failed", outbox_id=row.id)
        else:
            message = {**row.payload, "type": "sync", "collection": row.topic}
        await redis.publish(channel(row.org_id), json.dumps(message, default=str))
    await session.execute(
        update(OutboxEvent)
        .where(OutboxEvent.id.in_([r.id for r in rows]))
        .values(published_at=datetime.now(UTC))
    )
    await session.commit()
    return len(rows)


async def purge_published(session: AsyncSession, older_than: timedelta = timedelta(days=1)) -> None:
    await session.execute(
        delete(OutboxEvent).where(OutboxEvent.published_at < datetime.now(UTC) - older_than)
    )
    await session.commit()


async def run() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, json=settings.log_json)
    push: PushProvider = LoggingPushProvider()
    wake = asyncio.Event()
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    dsn = settings.database_url.replace("postgresql+asyncpg://", "postgresql://", 1)
    listener = await asyncpg.connect(dsn)
    await listener.add_listener("devpulse_outbox", lambda *_: wake.set())
    log.info("relay_started")
    last_purge = datetime.now(UTC)
    try:
        while not stop.is_set():
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(wake.wait(), timeout=POLL_S)
            wake.clear()
            try:
                async with get_sessionmaker()() as session:
                    while await relay_once(session, get_redis(), push) == BATCH:
                        pass
                    if datetime.now(UTC) - last_purge > timedelta(hours=1):
                        await purge_published(session)
                        last_purge = datetime.now(UTC)
            except Exception:
                log.exception("relay_iteration_failed")
                await asyncio.sleep(POLL_S)
    finally:
        await listener.close()
        log.info("relay_stopped")


if __name__ == "__main__":
    asyncio.run(run())

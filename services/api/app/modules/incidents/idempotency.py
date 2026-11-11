"""`Idempotency-Key` support for POST commands (offline replays from mobile, retries).

The command and the stored response commit in the same transaction, so a replay either
sees the stored response or the command never happened.
"""

import hashlib
import json
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Unprocessable
from app.core.tenancy import OrgContext
from app.modules.incidents.models import IdempotencyKey

TTL = timedelta(hours=24)


def fingerprint(method: str, path: str, body: BaseModel | None) -> str:
    payload = json.dumps(
        [method, path, body.model_dump(mode="json") if body else None], sort_keys=True
    )
    return hashlib.sha256(payload.encode()).hexdigest()


async def run_idempotent(
    session: AsyncSession,
    ctx: OrgContext,
    key: str | None,
    fp: str,
    command: Callable[[], Awaitable[BaseModel]],
    *,
    status_code: int = 200,
) -> JSONResponse:
    """Runs `command` (which must not commit) at most once per (user, key)."""
    if key is not None and not (1 <= len(key) <= 80):
        raise Unprocessable("Idempotency-Key must be 1-80 characters", code="idempotency.bad_key")
    if key is not None and ctx.user_id is not None:
        stored = await _load(session, ctx, key)
        if stored is not None:
            return _replay(stored, fp)

    result = await command()
    body: dict[str, Any] = result.model_dump(mode="json")
    if key is not None and ctx.user_id is not None:
        session.add(
            IdempotencyKey(
                user_id=ctx.user_id,
                key=key,
                org_id=ctx.org_id,
                fingerprint=fp,
                status_code=status_code,
                response=body,
            )
        )
    try:
        await session.commit()
    except IntegrityError:
        # A concurrent request with the same key won; return its response.
        await session.rollback()
        stored = await _load(session, ctx, key) if key else None
        if stored is None:
            raise
        return _replay(stored, fp)
    return JSONResponse(body, status_code=status_code)


async def _load(session: AsyncSession, ctx: OrgContext, key: str) -> IdempotencyKey | None:
    if ctx.user_id is None:
        return None
    row = await session.scalar(
        select(IdempotencyKey).where(
            IdempotencyKey.user_id == ctx.user_id, IdempotencyKey.key == key
        )
    )
    if row is not None and row.created_at < datetime.now(UTC) - TTL:
        await session.execute(
            delete(IdempotencyKey).where(
                IdempotencyKey.user_id == ctx.user_id, IdempotencyKey.key == key
            )
        )
        return None
    return row


def _replay(stored: IdempotencyKey, fp: str) -> JSONResponse:
    if stored.fingerprint != fp:
        raise Unprocessable(
            "This Idempotency-Key was already used for a different request",
            code="idempotency.key_reused",
        )
    return JSONResponse(
        stored.response, status_code=stored.status_code, headers={"Idempotent-Replayed": "true"}
    )

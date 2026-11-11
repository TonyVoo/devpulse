"""Ingest-key authentication for `/ingest/v1/*` (machine-to-machine)."""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

import structlog
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select, update

from app.core.config import get_settings
from app.core.deps import SessionDep
from app.core.errors import Forbidden, Unauthorized
from app.core.ratelimit import enforce_rate_limit
from app.core.redis import get_redis
from app.core.security import hash_token
from app.modules.services.models import IngestKey

_bearer = HTTPBearer(auto_error=False)
_LAST_USED_GRANULARITY = timedelta(minutes=1)


@dataclass(frozen=True)
class IngestPrincipal:
    key_id: UUID
    org_id: UUID
    service_id: UUID | None
    scopes: frozenset[str]
    is_demo: bool


def require_ingest_key(scope: str) -> Callable[..., Awaitable[IngestPrincipal]]:
    async def dependency(
        session: SessionDep,
        creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    ) -> IngestPrincipal:
        if creds is None or not creds.credentials.startswith("dp_ingest_"):
            raise Unauthorized(
                "Ingest key required",
                code="ingest.unauthorized",
                headers={"WWW-Authenticate": "Bearer"},
            )
        key = await session.scalar(
            select(IngestKey).where(IngestKey.key_hash == hash_token(creds.credentials))
        )
        if key is None or key.revoked_at is not None:
            raise Unauthorized("Invalid or revoked ingest key", code="ingest.invalid_key")
        if scope not in key.scopes:
            raise Forbidden(f"Ingest key lacks scope '{scope}'", code="ingest.scope_missing")
        await enforce_rate_limit(
            get_redis(),
            scope="ingest",
            key=str(key.id),
            limit=get_settings().ingest_rate_limit_per_min,
            window_s=60,
        )
        now = datetime.now(UTC)
        if key.last_used_at is None or now - key.last_used_at > _LAST_USED_GRANULARITY:
            # Throttled write: at most once a minute per key.
            await session.execute(
                update(IngestKey).where(IngestKey.id == key.id).values(last_used_at=now)
            )
        structlog.contextvars.bind_contextvars(org_id=str(key.org_id), ingest_key=str(key.id))
        return IngestPrincipal(
            key_id=key.id,
            org_id=key.org_id,
            service_id=key.service_id,
            scopes=frozenset(key.scopes),
            is_demo=key.is_demo,
        )

    return dependency

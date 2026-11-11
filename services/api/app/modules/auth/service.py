"""Authentication use cases: registration, login, refresh rotation, sessions, password change."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from redis.asyncio import Redis
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.deps import RequestMeta
from app.core.errors import Conflict, NotFound, Unauthorized
from app.core.ids import uuid7
from app.core.ratelimit import enforce_rate_limit
from app.core.security import (
    create_access_token,
    hash_password,
    hash_token,
    new_opaque_token,
    password_needs_rehash,
    verify_password,
)
from app.modules.auth.models import RefreshToken
from app.modules.auth.schemas import SessionOut, TokenPair
from app.modules.users.models import User

log = structlog.get_logger(__name__)

REFRESH_PREFIX = "dp_rt"


def _now() -> datetime:
    return datetime.now(UTC)


def _invalid_credentials() -> Unauthorized:
    return Unauthorized("Email or password is incorrect", code="auth.invalid_credentials")


def _invalid_refresh() -> Unauthorized:
    return Unauthorized("Refresh token is invalid or expired", code="auth.invalid_refresh")


async def _issue(
    session: AsyncSession, user: User, meta: RequestMeta, family_id: UUID | None = None
) -> TokenPair:
    s = get_settings()
    family = family_id or uuid7()
    raw = new_opaque_token(REFRESH_PREFIX)
    session.add(
        RefreshToken(
            user_id=user.id,
            family_id=family,
            token_hash=hash_token(raw),
            expires_at=_now() + timedelta(seconds=s.refresh_token_ttl_s),
            created_ip=meta.ip,
            user_agent=meta.user_agent,
        )
    )
    access, ttl = create_access_token(user.id, family)
    return TokenPair(access_token=access, refresh_token=raw, expires_in=ttl, session_id=family)


async def register(
    session: AsyncSession, *, email: str, password: str, display_name: str, meta: RequestMeta
) -> tuple[User, TokenPair]:
    user = User(email=email, password_hash=hash_password(password), display_name=display_name)
    session.add(user)
    try:
        await session.flush()
    except IntegrityError as e:
        await session.rollback()
        raise Conflict("An account with this email already exists", code="auth.email_taken") from e
    user.last_login_at = _now()
    tokens = await _issue(session, user, meta)
    await session.commit()
    log.info("user_registered", user_id=str(user.id))
    return user, tokens


async def login(
    session: AsyncSession, redis: Redis, *, email: str, password: str, meta: RequestMeta
) -> tuple[User, TokenPair]:
    s = get_settings()
    await enforce_rate_limit(
        redis,
        scope="login",
        key=f"{email}|{meta.ip}",
        limit=s.login_rate_limit,
        window_s=s.login_rate_window_s,
    )
    user = await session.scalar(select(User).where(User.email == email))
    # verify_password runs a hash even when the user is missing (timing equalisation).
    if not verify_password(password, user.password_hash if user else None) or user is None:
        raise _invalid_credentials()
    if user.disabled_at is not None:
        raise _invalid_credentials()
    if user.password_hash and password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)
    user.last_login_at = _now()
    tokens = await _issue(session, user, meta)
    await session.commit()
    return user, tokens


async def refresh(session: AsyncSession, *, raw_token: str, meta: RequestMeta) -> TokenPair:
    row = await session.scalar(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_token(raw_token))
        .with_for_update()
    )
    if row is None:
        raise _invalid_refresh()
    grace = timedelta(seconds=get_settings().refresh_reuse_grace_s)
    within_grace = (
        row.revoked_at is None and row.rotated_at is not None and _now() - row.rotated_at <= grace
    )
    if within_grace and await _family_active(session, row.family_id):
        user = await session.get(User, row.user_id)
        if user is None or user.disabled_at is not None or row.expires_at <= _now():
            raise _invalid_refresh()
        tokens = await _issue(session, user, meta, family_id=row.family_id)
        await session.commit()
        return tokens
    if row.rotated_at is not None or row.revoked_at is not None:
        # Reuse of a spent token: assume theft, kill the whole session family.
        await _revoke_family(session, row.user_id, row.family_id)
        await session.commit()
        log.warning("refresh_token_reuse", user_id=str(row.user_id), family_id=str(row.family_id))
        raise Unauthorized(
            "Session was revoked for security reasons, sign in again", code="auth.refresh_reused"
        )
    if row.expires_at <= _now():
        raise _invalid_refresh()
    user = await session.get(User, row.user_id)
    if user is None or user.disabled_at is not None:
        raise _invalid_refresh()
    row.rotated_at = _now()
    tokens = await _issue(session, user, meta, family_id=row.family_id)
    await session.commit()
    return tokens


async def _family_active(session: AsyncSession, family_id: UUID) -> bool:
    """A family is active while it has at least one unrevoked token."""
    found = await session.scalar(
        select(RefreshToken.id)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .limit(1)
    )
    return found is not None


async def _revoke_family(session: AsyncSession, user_id: UUID, family_id: UUID) -> int:
    result = await session.execute(
        update(RefreshToken)
        .where(
            RefreshToken.user_id == user_id,
            RefreshToken.family_id == family_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=_now())
    )
    return int(result.rowcount or 0)  # type: ignore[attr-defined]


async def logout(session: AsyncSession, *, user_id: UUID, family_id: UUID) -> None:
    await _revoke_family(session, user_id, family_id)
    await session.commit()


async def list_sessions(
    session: AsyncSession, *, user_id: UUID, current_family: UUID
) -> list[SessionOut]:
    heads = await session.scalars(
        select(RefreshToken)
        .where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.rotated_at.is_(None),
            RefreshToken.expires_at > _now(),
        )
        .order_by(RefreshToken.created_at.desc())
    )
    latest: dict[UUID, RefreshToken] = {}
    for h in heads:  # ordered newest first
        latest.setdefault(h.family_id, h)
    return [
        SessionOut(
            id=h.family_id,
            last_active_at=h.created_at,
            expires_at=h.expires_at,
            created_ip=h.created_ip,
            user_agent=h.user_agent,
            current=h.family_id == current_family,
        )
        for h in latest.values()
    ]


async def revoke_session(session: AsyncSession, *, user_id: UUID, family_id: UUID) -> None:
    if await _revoke_family(session, user_id, family_id) == 0:
        raise NotFound("Session not found", code="auth.session_not_found")
    await session.commit()


async def change_password(
    session: AsyncSession,
    *,
    user: User,
    current_password: str,
    new_password: str,
    meta: RequestMeta,
) -> TokenPair:
    if not verify_password(current_password, user.password_hash):
        raise Unauthorized("Current password is incorrect", code="auth.invalid_credentials")
    user.password_hash = hash_password(new_password)
    # Invalidate outstanding access tokens. iat has 1s precision, so tokens minted in this
    # same second stay valid — including the new one below (accepted 1s window).
    user.tokens_valid_after = _now().replace(microsecond=0)
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=_now())
    )
    tokens = await _issue(session, user, meta)
    await session.commit()
    return tokens

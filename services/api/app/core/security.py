"""Password hashing, JWT access tokens and opaque refresh/invitation tokens."""

import asyncio
import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from app.core.config import get_settings
from app.core.errors import Unauthorized

_hasher = PasswordHasher()  # argon2id with library defaults (OWASP-aligned)

# Used to equalise timing when the user does not exist.
_DUMMY_HASH = _hasher.hash("dummy-password-for-timing")

JWT_ALG = "HS256"


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


# argon2id is deliberately slow and memory-hard (~64 MB per hash). Run it in worker threads
# (the C code releases the GIL) so the event loop keeps serving other requests, and cap the
# concurrency so a burst of logins can't exhaust memory.
_HASH_SLOTS = asyncio.Semaphore(4)


async def hash_password_async(password: str) -> str:
    async with _HASH_SLOTS:
        return await asyncio.to_thread(hash_password, password)


async def verify_password_async(password: str, password_hash: str | None) -> bool:
    async with _HASH_SLOTS:
        return await asyncio.to_thread(verify_password, password, password_hash)


@dataclass(frozen=True)
class AccessClaims:
    user_id: UUID
    session_id: UUID
    issued_at: datetime


def create_access_token(user_id: UUID, session_id: UUID) -> tuple[str, int]:
    s = get_settings()
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "sid": str(session_id),
        "typ": "access",
        "iss": s.jwt_issuer,
        "aud": s.jwt_audience,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=s.access_token_ttl_s)).timestamp()),
        "jti": secrets.token_hex(8),
    }
    token = jwt.encode(payload, s.jwt_signing_key.get_secret_value(), algorithm=JWT_ALG)
    return token, s.access_token_ttl_s


def decode_access_token(token: str) -> AccessClaims:
    s = get_settings()
    try:
        payload = jwt.decode(
            token,
            s.jwt_signing_key.get_secret_value(),
            algorithms=[JWT_ALG],
            audience=s.jwt_audience,
            issuer=s.jwt_issuer,
            options={"require": ["exp", "iat", "sub", "sid", "typ"]},
        )
    except jwt.ExpiredSignatureError as e:
        raise Unauthorized("Access token expired", code="auth.token_expired") from e
    except jwt.PyJWTError as e:
        raise Unauthorized("Invalid access token", code="auth.invalid_token") from e
    if payload.get("typ") != "access":
        raise Unauthorized("Invalid access token", code="auth.invalid_token")
    try:
        return AccessClaims(
            user_id=UUID(payload["sub"]),
            session_id=UUID(payload["sid"]),
            issued_at=datetime.fromtimestamp(payload["iat"], UTC),
        )
    except (ValueError, TypeError) as e:
        raise Unauthorized("Invalid access token", code="auth.invalid_token") from e


def new_opaque_token(prefix: str) -> str:
    """URL-safe random token with a type prefix (helps secret scanners and debugging)."""
    return f"{prefix}_{secrets.token_urlsafe(32)}"


def hash_token(token: str) -> str:
    """Opaque tokens are high-entropy, so a fast hash is appropriate (no need for argon2)."""
    return hashlib.sha256(token.encode()).hexdigest()

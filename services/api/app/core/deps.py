"""Request-scoped dependencies: DB session, current user, request metadata."""

import hmac
from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import structlog
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_session
from app.core.errors import Unauthorized
from app.core.security import AccessClaims, decode_access_token
from app.modules.users.models import User

SessionDep = Annotated[AsyncSession, Depends(get_session)]

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class RequestMeta:
    ip: str | None
    user_agent: str | None
    request_id: str | None


BFF_CLIENT_IP_HEADER = "x-devpulse-client-ip"
BFF_SECRET_HEADER = "x-devpulse-bff-secret"  # noqa: S105 - a header name, not a secret


def client_ip(request: Request) -> str | None:
    """The caller's IP, without trusting anything a client can forge.

    1. The web BFF calls the API server-to-server and forwards the browser's IP; accepted
       only with the shared BFF secret (otherwise anyone could pick their own IP).
    2. Behind N trusted reverse proxies, the Nth entry from the right of X-Forwarded-For
       (those are appended by the proxies; anything to the left is client-supplied).
    3. Otherwise the TCP peer.
    """
    s = get_settings()
    secret = s.bff_shared_secret
    forwarded_client = request.headers.get(BFF_CLIENT_IP_HEADER)
    if secret is not None and forwarded_client:
        presented = request.headers.get(BFF_SECRET_HEADER, "")
        if hmac.compare_digest(presented.encode(), secret.get_secret_value().encode()):
            return forwarded_client.strip()[:64]
    if s.trusted_proxy_hops:
        chain = [
            p.strip() for p in request.headers.get("x-forwarded-for", "").split(",") if p.strip()
        ]
        if len(chain) >= s.trusted_proxy_hops:
            return chain[-s.trusted_proxy_hops][:64]
    return request.client.host if request.client else None


def get_request_meta(request: Request) -> RequestMeta:
    return RequestMeta(
        ip=client_ip(request),
        user_agent=(request.headers.get("user-agent") or "")[:512] or None,
        request_id=getattr(request.state, "request_id", None),
    )


RequestMetaDep = Annotated[RequestMeta, Depends(get_request_meta)]


@dataclass(frozen=True)
class CurrentUser:
    user: User
    claims: AccessClaims

    @property
    def id(self) -> UUID:
        return self.user.id


async def get_current_user(
    session: SessionDep,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> CurrentUser:
    if creds is None or creds.scheme.lower() != "bearer":
        raise Unauthorized(headers={"WWW-Authenticate": "Bearer"})
    claims = decode_access_token(creds.credentials)
    user = await session.get(User, claims.user_id)
    if user is None or user.disabled_at is not None:
        raise Unauthorized("Invalid access token", code="auth.invalid_token")
    # iat has second precision; compare at that precision.
    if user.tokens_valid_after and claims.issued_at < user.tokens_valid_after:
        raise Unauthorized("Session was revoked", code="auth.session_revoked")
    structlog.contextvars.bind_contextvars(user_id=str(user.id))
    return CurrentUser(user=user, claims=claims)


CurrentUserDep = Annotated[CurrentUser, Depends(get_current_user)]

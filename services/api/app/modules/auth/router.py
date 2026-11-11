from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from redis.asyncio import Redis

from app.core.deps import CurrentUserDep, RequestMetaDep, SessionDep
from app.core.redis import get_redis
from app.modules.auth import service
from app.modules.auth.schemas import AuthOut, LoginIn, RefreshIn, RegisterIn, SessionOut, TokenPair
from app.modules.users.schemas import ChangePasswordIn, UserOut

router = APIRouter(tags=["auth"])

RedisDep = Annotated[Redis, Depends(get_redis)]


@router.post("/auth/register", response_model=AuthOut, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterIn, session: SessionDep, meta: RequestMetaDep) -> AuthOut:
    user, tokens = await service.register(
        session,
        email=body.email,
        password=body.password,
        display_name=body.display_name,
        meta=meta,
    )
    return AuthOut(**tokens.model_dump(), user=UserOut.model_validate(user))


@router.post("/auth/login", response_model=AuthOut)
async def login(
    body: LoginIn, session: SessionDep, redis: RedisDep, meta: RequestMetaDep
) -> AuthOut:
    user, tokens = await service.login(
        session, redis, email=body.email, password=body.password, meta=meta
    )
    return AuthOut(**tokens.model_dump(), user=UserOut.model_validate(user))


@router.post("/auth/refresh", response_model=TokenPair)
async def refresh(body: RefreshIn, session: SessionDep, meta: RequestMetaDep) -> TokenPair:
    return await service.refresh(session, raw_token=body.refresh_token, meta=meta)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(current: CurrentUserDep, session: SessionDep) -> None:
    await service.logout(session, user_id=current.id, family_id=current.claims.session_id)


@router.get("/me/sessions", response_model=list[SessionOut])
async def list_sessions(current: CurrentUserDep, session: SessionDep) -> list[SessionOut]:
    return await service.list_sessions(
        session, user_id=current.id, current_family=current.claims.session_id
    )


@router.delete("/me/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_session(session_id: UUID, current: CurrentUserDep, session: SessionDep) -> None:
    await service.revoke_session(session, user_id=current.id, family_id=session_id)


@router.post("/me/password", response_model=TokenPair)
async def change_password(
    body: ChangePasswordIn, current: CurrentUserDep, session: SessionDep, meta: RequestMetaDep
) -> TokenPair:
    """Changes the password, signs out every other session and returns fresh tokens."""
    return await service.change_password(
        session,
        user=current.user,
        current_password=body.current_password,
        new_password=body.new_password,
        meta=meta,
    )

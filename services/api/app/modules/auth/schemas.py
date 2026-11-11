from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.modules.users.schemas import DisplayName, Email, Password, UserOut


class RegisterIn(BaseModel):
    email: Email
    password: Password
    display_name: DisplayName


class LoginIn(BaseModel):
    email: Email
    password: str = Field(min_length=1, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=256)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"  # noqa: S105 - not a secret
    expires_in: int
    session_id: UUID


class AuthOut(TokenPair):
    user: UserOut


class SessionOut(BaseModel):
    id: UUID
    last_active_at: datetime
    expires_at: datetime
    created_ip: str | None
    user_agent: str | None
    current: bool

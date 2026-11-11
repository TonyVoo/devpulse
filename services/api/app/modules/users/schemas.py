from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field, StringConstraints

from app.modules.rbac.permissions import Role


def _normalise_email(v: str) -> str:
    return v.strip().lower()


Email = Annotated[EmailStr, AfterValidator(_normalise_email)]
DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
# 12+ chars; length beats composition rules (NIST 800-63B). 128 cap bounds hashing cost.
Password = Annotated[str, StringConstraints(min_length=12, max_length=128)]
ThemePref = Literal["system", "dark", "light"]


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    display_name: str
    avatar_url: str | None
    theme_pref: ThemePref
    created_at: datetime


class OrgSummary(BaseModel):
    id: UUID
    slug: str
    name: str
    role: Role


class MeOut(UserOut):
    memberships: list[OrgSummary]


class UpdateMeIn(BaseModel):
    display_name: DisplayName | None = None
    theme_pref: ThemePref | None = None


class ChangePasswordIn(BaseModel):
    current_password: str = Field(max_length=128)
    new_password: Password


class DeviceIn(BaseModel):
    platform: Literal["ios", "android", "web"]
    fcm_token: Annotated[str, StringConstraints(min_length=10, max_length=4096)]
    app_version: Annotated[str, StringConstraints(max_length=32)] | None = None


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    platform: str
    app_version: str | None
    last_seen_at: datetime | None

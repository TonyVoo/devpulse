from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints

from app.modules.rbac.permissions import Role
from app.modules.users.schemas import Email

OrgName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=120)]
Slug = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        min_length=3,
        max_length=48,
        pattern=r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$",
    ),
]


class OrgCreateIn(BaseModel):
    name: OrgName
    slug: Slug | None = None


class OrgUpdateIn(BaseModel):
    name: OrgName | None = None


class OrgOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    slug: str
    name: str
    created_at: datetime


class OrgWithRoleOut(OrgOut):
    role: Role


class MemberOut(BaseModel):
    user_id: UUID
    email: str
    display_name: str
    avatar_url: str | None
    role: Role
    joined_at: datetime


class MemberUpdateIn(BaseModel):
    role: Role


class InvitationCreateIn(BaseModel):
    email: Email
    role: Role = Role.ENGINEER


class InvitationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    role: Role
    expires_at: datetime
    created_at: datetime


class InvitationCreatedOut(InvitationOut):
    # Returned exactly once. Email delivery arrives with the notifications module (Phase 3);
    # until then the inviter shares the token/link out of band.
    token: str


class InvitationAcceptOut(BaseModel):
    org: OrgWithRoleOut

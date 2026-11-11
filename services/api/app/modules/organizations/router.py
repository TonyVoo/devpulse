from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.core.deps import CurrentUserDep, RequestMetaDep, SessionDep
from app.core.tenancy import OrgContext, require_org
from app.modules.organizations import service
from app.modules.organizations.schemas import (
    InvitationAcceptOut,
    InvitationCreatedOut,
    InvitationCreateIn,
    InvitationOut,
    MemberOut,
    MemberUpdateIn,
    OrgCreateIn,
    OrgUpdateIn,
    OrgWithRoleOut,
)
from app.modules.rbac.permissions import Permission

router = APIRouter(tags=["organizations"])

Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]
Manage = Annotated[OrgContext, Depends(require_org(Permission.ORG_MANAGE))]
Delete = Annotated[OrgContext, Depends(require_org(Permission.ORG_DELETE))]
Members = Annotated[OrgContext, Depends(require_org(Permission.MEMBERS_MANAGE))]


@router.post("/orgs", response_model=OrgWithRoleOut, status_code=status.HTTP_201_CREATED)
async def create_org(
    body: OrgCreateIn, current: CurrentUserDep, session: SessionDep, meta: RequestMetaDep
) -> OrgWithRoleOut:
    return await service.create_org(
        session, user=current.user, name=body.name, slug=body.slug, meta=meta
    )


@router.get("/orgs", response_model=list[OrgWithRoleOut])
async def list_orgs(current: CurrentUserDep, session: SessionDep) -> list[OrgWithRoleOut]:
    return await service.list_user_orgs(session, current.id)


@router.get("/orgs/{org_id}", response_model=OrgWithRoleOut)
async def get_org(ctx: Read, session: SessionDep) -> OrgWithRoleOut:
    return await service.OrgService(session, ctx).get()


@router.patch("/orgs/{org_id}", response_model=OrgWithRoleOut)
async def update_org(
    body: OrgUpdateIn, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> OrgWithRoleOut:
    return await service.OrgService(session, ctx).update(name=body.name, meta=meta)


@router.delete("/orgs/{org_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_org(ctx: Delete, session: SessionDep, meta: RequestMetaDep) -> None:
    await service.OrgService(session, ctx).soft_delete(meta=meta)


@router.get("/orgs/{org_id}/members", response_model=list[MemberOut])
async def list_members(ctx: Read, session: SessionDep) -> list[MemberOut]:
    return await service.OrgService(session, ctx).list_members()


@router.patch("/orgs/{org_id}/members/{user_id}", response_model=MemberOut)
async def update_member(
    user_id: UUID, body: MemberUpdateIn, ctx: Members, session: SessionDep, meta: RequestMetaDep
) -> MemberOut:
    return await service.OrgService(session, ctx).change_role(
        user_id=user_id, role=body.role, meta=meta
    )


@router.delete("/orgs/{org_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    user_id: UUID, ctx: Read, session: SessionDep, meta: RequestMetaDep
) -> None:
    """Members may remove themselves (leave); removing others needs members.manage."""
    await service.OrgService(session, ctx).remove_member(user_id=user_id, meta=meta)


@router.get("/orgs/{org_id}/invitations", response_model=list[InvitationOut])
async def list_invitations(ctx: Members, session: SessionDep) -> list[InvitationOut]:
    invs = await service.OrgService(session, ctx).list_invitations()
    return [InvitationOut.model_validate(i) for i in invs]


@router.post(
    "/orgs/{org_id}/invitations",
    response_model=InvitationCreatedOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_invitation(
    body: InvitationCreateIn, ctx: Members, session: SessionDep, meta: RequestMetaDep
) -> InvitationCreatedOut:
    inv, token = await service.OrgService(session, ctx).invite(
        email=body.email, role=body.role, meta=meta
    )
    return InvitationCreatedOut(**InvitationOut.model_validate(inv).model_dump(), token=token)


@router.delete("/orgs/{org_id}/invitations/{invitation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_invitation(
    invitation_id: UUID, ctx: Members, session: SessionDep, meta: RequestMetaDep
) -> None:
    await service.OrgService(session, ctx).revoke_invitation(invitation_id=invitation_id, meta=meta)


@router.post("/invitations/{token}/accept", response_model=InvitationAcceptOut)
async def accept_invitation(
    token: str, current: CurrentUserDep, session: SessionDep, meta: RequestMetaDep
) -> InvitationAcceptOut:
    org = await service.accept_invitation(session, user=current.user, raw_token=token, meta=meta)
    return InvitationAcceptOut(org=org)

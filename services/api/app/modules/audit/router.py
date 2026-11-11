from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.core.deps import SessionDep
from app.core.pagination import Page
from app.core.tenancy import OrgContext, require_org
from app.modules.audit.service import AuditLogOut, AuditRepository
from app.modules.rbac.permissions import Permission

router = APIRouter(prefix="/orgs/{org_id}/audit-logs", tags=["audit"])


@router.get("", response_model=Page[AuditLogOut])
async def list_audit_logs(
    session: SessionDep,
    ctx: Annotated[OrgContext, Depends(require_org(Permission.AUDIT_READ))],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    cursor: str | None = None,
    action: str | None = None,
) -> Page[AuditLogOut]:
    return await AuditRepository(session, ctx).list(limit=limit, cursor=cursor, action=action)

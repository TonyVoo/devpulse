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
    action_prefix: Annotated[str | None, Query(max_length=40)] = None,
) -> Page[AuditLogOut]:
    """`action` matches exactly; `action_prefix` filters a family, e.g. `member.` or `ai.`."""
    return await AuditRepository(session, ctx).list(
        limit=limit, cursor=cursor, action=action, action_prefix=action_prefix
    )

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.deps import SessionDep
from app.core.tenancy import OrgContext, require_org
from app.modules.alerts.models import Severity
from app.modules.notifications.models import NotificationPreference
from app.modules.rbac.permissions import Permission

router = APIRouter(prefix="/orgs/{org_id}/notification-preferences", tags=["notifications"])
Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]


class PreferencesIO(BaseModel):
    push_enabled: bool = True
    min_severity: Severity = Severity.SEV2
    only_assigned: bool = False


@router.get("", response_model=PreferencesIO)
async def get_preferences(ctx: Read, session: SessionDep) -> PreferencesIO:
    pref = await session.get(NotificationPreference, (ctx.user_id, ctx.org_id))
    if pref is None:
        return PreferencesIO()
    return PreferencesIO(
        push_enabled=pref.push_enabled,
        min_severity=pref.min_severity,
        only_assigned=pref.only_assigned,
    )


@router.put("", response_model=PreferencesIO)
async def put_preferences(body: PreferencesIO, ctx: Read, session: SessionDep) -> PreferencesIO:
    pref = await session.get(NotificationPreference, (ctx.user_id, ctx.org_id))
    if pref is None:
        pref = NotificationPreference(user_id=ctx.user_id, org_id=ctx.org_id)
        session.add(pref)
    pref.push_enabled, pref.min_severity, pref.only_assigned = (
        body.push_enabled,
        body.min_severity,
        body.only_assigned,
    )
    await session.commit()
    return body

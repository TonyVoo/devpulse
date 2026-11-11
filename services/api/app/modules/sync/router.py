"""Incremental sync feed for offline-first clients (API.md §6, ADR-019).

`GET /orgs/{org_id}/sync/{collection}?cursor=<change_seq>` returns every row of the
collection changed after `cursor`, in `change_seq` order. Because the database stamps
`change_seq` under a per-org lock held until commit, the visible rows of an org always form
a gap-free prefix: a client that stores `next_cursor` can never skip a change.
"""

from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import SessionDep
from app.core.tenancy import OrgContext, require_org
from app.modules.deployments.models import Deployment
from app.modules.deployments.service import DeploymentOut
from app.modules.incidents.models import Incident, IncidentStatus
from app.modules.incidents.service import IncidentService, _row_to_out
from app.modules.rbac.permissions import Permission
from app.modules.services.models import Service
from app.modules.services.schemas import ServiceOut

router = APIRouter(prefix="/orgs/{org_id}/sync", tags=["sync"])

Collection = Literal["services", "incidents", "deployments"]
MAX_LIMIT = 500
# First sync (cursor=0) only ships what a phone needs offline; older rows still arrive later
# if they change.
INITIAL_WINDOW = timedelta(days=7)


class Change(BaseModel):
    op: Literal["upsert", "delete"]
    id: UUID
    change_seq: int
    data: dict[str, Any] | None


class SyncPage(BaseModel):
    collection: Collection
    changes: list[Change]
    next_cursor: int
    has_more: bool


async def _max_seq(session: AsyncSession, model: Any, org_id: UUID) -> int:
    value = await session.scalar(select(func.max(model.change_seq)).where(model.org_id == org_id))
    return int(value or 0)


async def _services(
    session: AsyncSession, ctx: OrgContext, cursor: int, limit: int
) -> tuple[list[Change], bool]:
    stmt = select(Service).where(Service.org_id == ctx.org_id, Service.change_seq > cursor)
    if cursor == 0:
        stmt = stmt.where(Service.deleted_at.is_(None))
    rows = list((await session.scalars(stmt.order_by(Service.change_seq).limit(limit + 1))).all())
    changes = []
    for s in rows[:limit]:
        deleted = s.deleted_at is not None
        changes.append(
            Change(
                op="delete" if deleted else "upsert",
                id=s.id,
                change_seq=s.change_seq,
                data=None if deleted else ServiceOut.model_validate(s).model_dump(mode="json"),
            )
        )
    return changes, len(rows) > limit


async def _incidents(
    session: AsyncSession, ctx: OrgContext, cursor: int, limit: int
) -> tuple[list[Change], bool]:
    stmt = IncidentService(session, ctx)._base().where(Incident.change_seq > cursor)
    if cursor == 0:
        since = datetime.now(UTC) - INITIAL_WINDOW
        stmt = stmt.where(
            or_(Incident.status != IncidentStatus.RESOLVED, Incident.resolved_at >= since)
        )
    rows = (await session.execute(stmt.order_by(Incident.change_seq).limit(limit + 1))).all()
    changes = [
        Change(
            op="upsert",
            id=inc.id,
            change_seq=inc.change_seq,
            data=_row_to_out(inc, name, slug, who).model_dump(mode="json"),
        )
        for inc, name, slug, who in rows[:limit]
    ]
    return changes, len(rows) > limit


async def _deployments(
    session: AsyncSession, ctx: OrgContext, cursor: int, limit: int
) -> tuple[list[Change], bool]:
    stmt = (
        select(Deployment, Service.name)
        .join(Service, Service.id == Deployment.service_id)
        .where(Deployment.org_id == ctx.org_id, Deployment.change_seq > cursor)
    )
    if cursor == 0:
        stmt = stmt.where(Deployment.started_at >= datetime.now(UTC) - INITIAL_WINDOW)
    rows = (await session.execute(stmt.order_by(Deployment.change_seq).limit(limit + 1))).all()
    changes = [
        Change(
            op="upsert",
            id=d.id,
            change_seq=d.change_seq,
            data=DeploymentOut.model_validate(d)
            .model_copy(update={"service_name": name})
            .model_dump(mode="json"),
        )
        for d, name in rows[:limit]
    ]
    return changes, len(rows) > limit


_HANDLERS = {
    "services": (_services, Service),
    "incidents": (_incidents, Incident),
    "deployments": (_deployments, Deployment),
}


@router.get("/{collection}", response_model=SyncPage)
async def sync(
    collection: Collection,
    ctx: Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))],
    session: SessionDep,
    cursor: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = MAX_LIMIT,
) -> SyncPage:
    handler, model = _HANDLERS[collection]
    changes, has_more = await handler(session, ctx, cursor, limit)
    if has_more:
        next_cursor = changes[-1].change_seq
    else:
        # Everything up to the org's current max is either delivered or deliberately outside
        # the initial window; resuming from the max never skips a later change.
        next_cursor = max(cursor, await _max_seq(session, model, ctx.org_id))
    return SyncPage(
        collection=collection, changes=changes, next_cursor=next_cursor, has_more=has_more
    )

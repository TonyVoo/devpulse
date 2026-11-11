"""Deployments: listing, ingestion (CI/CD via ingest key) and upsert used by GitHub."""

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, ConfigDict, StringConstraints
from sqlalchemy import and_, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import SessionDep
from app.core.errors import NotFound
from app.core.ids import uuid7
from app.core.pagination import MAX_LIMIT, Page, decode_cursor, encode_cursor
from app.core.tenancy import OrgContext, OrgScopedRepository, require_org
from app.modules.deployments.models import BuildStatus, Deployment, DeploySource, DeployStatus
from app.modules.rbac.permissions import Permission
from app.modules.services.models import Service
from app.modules.services.schemas import Environment, ServiceSlug
from app.modules.telemetry.ingest import resolve_service
from app.modules.telemetry.ingest_auth import IngestPrincipal, require_ingest_key


class DeploymentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    service_id: UUID
    service_name: str = ""
    environment: str
    version: str
    commit_sha: str | None
    commit_message: str | None
    commit_author: str | None
    branch: str | None
    repo_url: str | None
    build_status: BuildStatus | None
    status: DeployStatus
    started_at: datetime
    finished_at: datetime | None
    source: DeploySource
    is_demo: bool


class DeploymentIn(BaseModel):
    service: ServiceSlug
    environment: Environment = "production"
    version: Annotated[str, StringConstraints(min_length=1, max_length=80)]
    external_id: Annotated[str, StringConstraints(min_length=1, max_length=120)]
    status: DeployStatus = DeployStatus.STARTED
    build_status: BuildStatus | None = None
    commit_sha: Annotated[str, StringConstraints(max_length=64)] | None = None
    commit_message: Annotated[str, StringConstraints(max_length=4000)] | None = None
    commit_author: Annotated[str, StringConstraints(max_length=120)] | None = None
    branch: Annotated[str, StringConstraints(max_length=200)] | None = None
    repo_url: Annotated[str, StringConstraints(max_length=512)] | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None


async def upsert_deployment(
    session: AsyncSession,
    *,
    org_id: UUID,
    service_id: UUID,
    source: DeploySource,
    external_id: str,
    values: dict[str, object],
    is_demo: bool = False,
    insert_only: frozenset[str] = frozenset(),
) -> Deployment:
    """Idempotent on (org, source, external_id): re-sent events update the same row."""
    now = datetime.now(UTC)
    row = {
        "org_id": org_id,
        "service_id": service_id,
        "source": source,
        "external_id": external_id,
        "is_demo": is_demo,
        **values,
    }
    if row.get("started_at") is None:  # explicit None from the payload counts as "not sent"
        row["started_at"] = now
    update_cols = {
        k: v
        for k, v in values.items()
        if v is not None and k != "started_at" and k not in insert_only
    }
    upsert = pg_insert(Deployment).values(id=uuid7(), **row)
    stmt = upsert.on_conflict_do_update(
        index_elements=["org_id", "source", "external_id"],
        set_={**update_cols, "updated_at": now},
    ).returning(Deployment.id)
    dep_id = (await session.execute(stmt)).scalar_one()
    dep = await session.get(Deployment, dep_id, populate_existing=True)
    if dep is None:  # pragma: no cover - the row was just written in this transaction
        raise RuntimeError("upserted deployment not found")
    return dep


class Deployments(OrgScopedRepository):
    async def page(
        self,
        *,
        limit: int,
        cursor: str | None,
        service_id: UUID | None,
        status: DeployStatus | None,
        since: datetime | None,
    ) -> Page[DeploymentOut]:
        limit = max(1, min(limit, MAX_LIMIT))
        stmt = (
            select(Deployment, Service.name)
            .join(Service, Service.id == Deployment.service_id)
            .where(Deployment.org_id == self.ctx.org_id)
        )
        if service_id:
            stmt = stmt.where(Deployment.service_id == service_id)
        if status:
            stmt = stmt.where(Deployment.status == status)
        if since:
            stmt = stmt.where(Deployment.started_at >= since)
        if cursor:
            ts, last_id = decode_cursor(cursor)
            stmt = stmt.where(
                or_(
                    Deployment.started_at < ts,
                    and_(Deployment.started_at == ts, Deployment.id < last_id),
                )
            )
        rows = (
            await self.session.execute(
                stmt.order_by(Deployment.started_at.desc(), Deployment.id.desc()).limit(limit + 1)
            )
        ).all()
        items = [
            DeploymentOut.model_validate(d).model_copy(update={"service_name": n})
            for d, n in rows[:limit]
        ]
        nxt = encode_cursor(items[-1].started_at, items[-1].id) if len(rows) > limit else None
        return Page(items=items, next_cursor=nxt)

    async def get(self, dep_id: UUID) -> DeploymentOut:
        row = (
            await self.session.execute(
                select(Deployment, Service.name)
                .join(Service, Service.id == Deployment.service_id)
                .where(Deployment.org_id == self.ctx.org_id, Deployment.id == dep_id)
            )
        ).first()
        if row is None:
            raise NotFound("Deployment not found", code="deployment.not_found")
        return DeploymentOut.model_validate(row[0]).model_copy(update={"service_name": row[1]})


router = APIRouter(tags=["deployments"])
ingest_router = APIRouter(tags=["ingest"])
Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]


@router.get("/orgs/{org_id}/deployments", response_model=Page[DeploymentOut])
async def list_deployments(
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    cursor: str | None = None,
    service_id: UUID | None = None,
    status_: Annotated[DeployStatus | None, Query(alias="status")] = None,
    since: datetime | None = None,
) -> Page[DeploymentOut]:
    return await Deployments(session, ctx).page(
        limit=limit, cursor=cursor, service_id=service_id, status=status_, since=since
    )


@router.get("/orgs/{org_id}/deployments/{deployment_id}", response_model=DeploymentOut)
async def get_deployment(deployment_id: UUID, ctx: Read, session: SessionDep) -> DeploymentOut:
    return await Deployments(session, ctx).get(deployment_id)


@ingest_router.post(
    "/ingest/v1/deployments", response_model=DeploymentOut, status_code=status.HTTP_202_ACCEPTED
)
async def ingest_deployment(
    body: DeploymentIn,
    session: SessionDep,
    principal: Annotated[IngestPrincipal, Depends(require_ingest_key("deployments:write"))],
) -> DeploymentOut:
    """For CI/CD pipelines: send `started` then `succeeded`/`failed` with the same external_id."""
    svc = await resolve_service(session, principal, body.service, body.environment)
    values = body.model_dump(exclude={"service", "external_id"})
    dep = await upsert_deployment(
        session,
        org_id=principal.org_id,
        service_id=svc.id,
        source=DeploySource.API,
        external_id=body.external_id,
        values=values,
        is_demo=principal.is_demo,
    )
    await session.commit()
    return DeploymentOut.model_validate(dep).model_copy(update={"service_name": svc.name})

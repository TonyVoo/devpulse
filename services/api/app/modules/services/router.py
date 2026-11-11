from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Response, status

from app.core.deps import RequestMetaDep, SessionDep
from app.core.pagination import Page
from app.core.tenancy import OrgContext, require_org
from app.modules.rbac.permissions import Permission
from app.modules.services.models import Health
from app.modules.services.schemas import (
    IngestKeyCreatedOut,
    IngestKeyCreateIn,
    IngestKeyOut,
    ServiceCreateIn,
    ServiceOut,
    ServiceUpdateIn,
)
from app.modules.services.service import ServiceCatalog

router = APIRouter(prefix="/orgs/{org_id}", tags=["services"])

Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]
Manage = Annotated[OrgContext, Depends(require_org(Permission.SERVICES_MANAGE))]


def _etag(response: Response, version: int) -> None:
    response.headers["ETag"] = f'"{version}"'


@router.get("/services", response_model=Page[ServiceOut])
async def list_services(
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    cursor: str | None = None,
    health: Annotated[list[Health] | None, Query()] = None,
    environment: str | None = None,
    q: Annotated[str | None, Query(max_length=80)] = None,
) -> Page[ServiceOut]:
    return await ServiceCatalog(session, ctx).page(
        limit=limit, cursor=cursor, health=health, environment=environment, q=q
    )


@router.post("/services", response_model=ServiceOut, status_code=status.HTTP_201_CREATED)
async def create_service(
    body: ServiceCreateIn,
    ctx: Manage,
    session: SessionDep,
    meta: RequestMetaDep,
    response: Response,
) -> ServiceOut:
    svc = await ServiceCatalog(session, ctx).create(body, meta)
    _etag(response, svc.version)
    return ServiceOut.model_validate(svc)


@router.get("/services/{service_id}", response_model=ServiceOut)
async def get_service(
    service_id: UUID, ctx: Read, session: SessionDep, response: Response
) -> ServiceOut:
    svc = await ServiceCatalog(session, ctx).get(service_id)
    _etag(response, svc.version)
    return ServiceOut.model_validate(svc)


@router.patch("/services/{service_id}", response_model=ServiceOut)
async def update_service(
    service_id: UUID,
    body: ServiceUpdateIn,
    ctx: Manage,
    session: SessionDep,
    meta: RequestMetaDep,
    response: Response,
    if_match: Annotated[str | None, Header()] = None,
) -> ServiceOut:
    svc = await ServiceCatalog(session, ctx).update(service_id, body, if_match, meta)
    _etag(response, svc.version)
    return ServiceOut.model_validate(svc)


@router.delete("/services/{service_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_service(
    service_id: UUID, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> None:
    await ServiceCatalog(session, ctx).delete(service_id, meta)


@router.get("/ingest-keys", response_model=list[IngestKeyOut])
async def list_ingest_keys(ctx: Manage, session: SessionDep) -> list[IngestKeyOut]:
    return [IngestKeyOut.model_validate(k) for k in await ServiceCatalog(session, ctx).list_keys()]


@router.post(
    "/ingest-keys", response_model=IngestKeyCreatedOut, status_code=status.HTTP_201_CREATED
)
async def create_ingest_key(
    body: IngestKeyCreateIn, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> IngestKeyCreatedOut:
    key, raw = await ServiceCatalog(session, ctx).create_key(body, meta)
    return IngestKeyCreatedOut(**IngestKeyOut.model_validate(key).model_dump(), key=raw)


@router.delete("/ingest-keys/{key_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_ingest_key(
    key_id: UUID, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> None:
    await ServiceCatalog(session, ctx).revoke_key(key_id, meta)

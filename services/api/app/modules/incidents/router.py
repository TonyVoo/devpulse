import json
from collections.abc import Awaitable, Callable
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request, Response, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import SessionDep
from app.core.pagination import Page
from app.core.tenancy import OrgContext, require_org
from app.modules.alerts.models import Severity
from app.modules.incidents.idempotency import fingerprint, run_idempotent
from app.modules.incidents.models import IncidentStatus
from app.modules.incidents.schemas import (
    AssignIn,
    CommentIn,
    CommentOut,
    CorrelatedDeploymentOut,
    CorrelationIn,
    EscalateIn,
    EventOut,
    IncidentCreateIn,
    IncidentOut,
    ReopenIn,
    ResolveIn,
    SeverityIn,
)
from app.modules.incidents.service import IncidentService
from app.modules.rbac.permissions import Permission

router = APIRouter(prefix="/orgs/{org_id}/incidents", tags=["incidents"])

Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]
Act = Annotated[OrgContext, Depends(require_org(Permission.INCIDENTS_ACT))]
IfMatch = Annotated[str | None, Header()]
IdemKey = Annotated[str | None, Header(alias="Idempotency-Key")]


@router.get("", response_model=Page[IncidentOut])
async def list_incidents(
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    cursor: str | None = None,
    status_: Annotated[list[IncidentStatus] | None, Query(alias="status")] = None,
    severity: Annotated[list[Severity] | None, Query()] = None,
    service_id: UUID | None = None,
    assignee: Annotated[str | None, Query(pattern="^(me|none)$")] = None,
    q: Annotated[str | None, Query(max_length=80)] = None,
) -> Page[IncidentOut]:
    return await IncidentService(session, ctx).page(
        limit=limit,
        cursor=cursor,
        status=status_,
        severity=severity,
        service_id=service_id,
        assignee=assignee,
        q=q,
    )


@router.post("", response_model=IncidentOut, status_code=status.HTTP_201_CREATED)
async def create_incident(
    body: IncidentCreateIn, ctx: Act, session: SessionDep, request: Request, idem: IdemKey = None
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await run_idempotent(
        session,
        ctx,
        idem,
        fingerprint("POST", request.url.path, body),
        lambda: svc.create(
            title=body.title,
            severity=body.severity,
            service_id=body.service_id,
            summary=body.summary,
        ),
        status_code=201,
    )


@router.get("/{ref}", response_model=IncidentOut)
async def get_incident(ref: str, ctx: Read, session: SessionDep, response: Response) -> IncidentOut:
    """`ref` is the incident UUID or its key (`INC-1024`)."""
    out = await IncidentService(session, ctx).get(ref)
    response.headers["ETag"] = f'"{out.version}"'
    return out


async def _command(
    request: Request,
    session: AsyncSession,
    ctx: OrgContext,
    idem: str | None,
    body: BaseModel | None,
    call: Callable[[], Awaitable[BaseModel]],
) -> JSONResponse:
    resp = await run_idempotent(
        session, ctx, idem, fingerprint("POST", request.url.path, body), call
    )
    if resp.status_code == 200:
        version = json.loads(bytes(resp.body)).get("version")
        if version is not None:
            resp.headers["ETag"] = f'"{version}"'
    return resp


@router.post("/{ref}/acknowledge", response_model=IncidentOut)
async def acknowledge(
    ref: str,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(request, session, ctx, idem, None, lambda: svc.acknowledge(ref, if_match))


@router.post("/{ref}/resolve", response_model=IncidentOut)
async def resolve(
    ref: str,
    body: ResolveIn,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(
        request,
        session,
        ctx,
        idem,
        body,
        lambda: svc.resolve(ref, if_match, body.resolution_note, body.root_cause),
    )


@router.post("/{ref}/reopen", response_model=IncidentOut)
async def reopen(
    ref: str,
    body: ReopenIn,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(
        request, session, ctx, idem, body, lambda: svc.reopen(ref, if_match, body.reason)
    )


@router.post("/{ref}/assign", response_model=IncidentOut)
async def assign(
    ref: str,
    body: AssignIn,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(
        request, session, ctx, idem, body, lambda: svc.assign(ref, if_match, body.user_id)
    )


@router.post("/{ref}/escalate", response_model=IncidentOut)
async def escalate(
    ref: str,
    body: EscalateIn,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(
        request, session, ctx, idem, body, lambda: svc.escalate(ref, if_match, body.reason)
    )


@router.post("/{ref}/severity", response_model=IncidentOut)
async def set_severity(
    ref: str,
    body: SeverityIn,
    ctx: Act,
    session: SessionDep,
    request: Request,
    if_match: IfMatch = None,
    idem: IdemKey = None,
) -> JSONResponse:
    svc = IncidentService(session, ctx)
    return await _command(
        request, session, ctx, idem, body, lambda: svc.set_severity(ref, if_match, body.severity)
    )


@router.get("/{ref}/timeline", response_model=Page[EventOut])
async def timeline(
    ref: str,
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 100,
    cursor: str | None = None,
) -> Page[EventOut]:
    return await IncidentService(session, ctx).timeline(ref, limit=limit, cursor=cursor)


@router.get("/{ref}/comments", response_model=Page[CommentOut])
async def list_comments(
    ref: str,
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 100,
    cursor: str | None = None,
) -> Page[CommentOut]:
    return await IncidentService(session, ctx).comments(ref, limit=limit, cursor=cursor)


@router.post("/{ref}/comments", response_model=CommentOut, status_code=status.HTTP_201_CREATED)
async def add_comment(
    ref: str, body: CommentIn, ctx: Act, session: SessionDep, response: Response
) -> CommentOut:
    comment, created = await IncidentService(session, ctx).add_comment(
        ref, body.body, body.client_id
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return comment


@router.get("/{ref}/deployments", response_model=list[CorrelatedDeploymentOut])
async def correlated_deployments(
    ref: str, ctx: Read, session: SessionDep
) -> list[CorrelatedDeploymentOut]:
    return await IncidentService(session, ctx).deployments(ref)


@router.put("/{ref}/deployments/{deployment_id}", response_model=CorrelatedDeploymentOut)
async def set_correlation(
    ref: str, deployment_id: UUID, body: CorrelationIn, ctx: Act, session: SessionDep
) -> CorrelatedDeploymentOut:
    return await IncidentService(session, ctx).set_correlation(ref, deployment_id, body.correlation)

"""AI investigator API (docs/API.md § AI). Provider keys never pass through here."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status

from app.core.deps import SessionDep
from app.core.pagination import Page
from app.core.tenancy import OrgContext, require_org
from app.modules.ai.schemas import (
    AISettingsIn,
    AISettingsOut,
    AskIn,
    AskOut,
    DecisionIn,
    FeedbackIn,
    InvestigationOut,
    InvestigationSummary,
    MessageOut,
    ProposalOut,
    UsageOut,
)
from app.modules.ai.service import AIService
from app.modules.rbac.permissions import Permission

router = APIRouter(prefix="/orgs/{org_id}", tags=["ai"])

Read = Annotated[OrgContext, Depends(require_org(Permission.ORG_READ))]
Investigate = Annotated[OrgContext, Depends(require_org(Permission.AI_INVESTIGATE))]
Configure = Annotated[OrgContext, Depends(require_org(Permission.AI_CONFIGURE))]


@router.post(
    "/incidents/{ref}/investigations",
    response_model=InvestigationOut,
    status_code=status.HTTP_202_ACCEPTED,
)
async def start_investigation(ref: str, ctx: Investigate, session: SessionDep) -> InvestigationOut:
    """Queues an analysis (one active run per incident). Poll the returned investigation or
    listen for the incident's `ai_analysis` timeline event."""
    return await AIService(session, ctx).start(ref)


@router.get("/incidents/{ref}/investigations", response_model=list[InvestigationSummary])
async def incident_investigations(
    ref: str, ctx: Read, session: SessionDep
) -> list[InvestigationSummary]:
    return await AIService(session, ctx).for_incident(ref)


@router.get("/ai/investigations", response_model=Page[InvestigationSummary])
async def list_investigations(
    ctx: Read,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
    cursor: str | None = None,
) -> Page[InvestigationSummary]:
    return await AIService(session, ctx).page(limit=limit, cursor=cursor)


@router.get("/ai/investigations/{inv_id}", response_model=InvestigationOut)
async def get_investigation(inv_id: UUID, ctx: Read, session: SessionDep) -> InvestigationOut:
    return await AIService(session, ctx).get(inv_id)


@router.get("/ai/investigations/{inv_id}/messages", response_model=list[MessageOut])
async def list_messages(inv_id: UUID, ctx: Read, session: SessionDep) -> list[MessageOut]:
    return await AIService(session, ctx).messages(inv_id)


@router.post("/ai/investigations/{inv_id}/messages", response_model=AskOut)
async def ask(inv_id: UUID, body: AskIn, ctx: Investigate, session: SessionDep) -> AskOut:
    """Follow-up question. The model may call read-only tools; their results become new
    evidence. Idempotent on `client_id` (a retry returns the stored answer)."""
    return await AIService(session, ctx).ask(inv_id, body)


@router.post(
    "/ai/investigations/{inv_id}/proposals/{proposal_id}/decision", response_model=ProposalOut
)
async def decide(
    inv_id: UUID, proposal_id: UUID, body: DecisionIn, ctx: Investigate, session: SessionDep
) -> ProposalOut:
    """Records a human approval/rejection. DevPulse never executes the action."""
    return await AIService(session, ctx).decide(inv_id, proposal_id, body)


@router.put("/ai/investigations/{inv_id}/feedback", status_code=status.HTTP_204_NO_CONTENT)
async def feedback(inv_id: UUID, body: FeedbackIn, ctx: Read, session: SessionDep) -> Response:
    await AIService(session, ctx).feedback(inv_id, body)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/ai/settings", response_model=AISettingsOut)
async def get_ai_settings(ctx: Read, session: SessionDep) -> AISettingsOut:
    return await AIService(session, ctx).settings()


@router.put("/ai/settings", response_model=AISettingsOut)
async def put_ai_settings(body: AISettingsIn, ctx: Configure, session: SessionDep) -> AISettingsOut:
    return await AIService(session, ctx).update_settings(body)


@router.get("/ai/usage", response_model=UsageOut)
async def ai_usage(
    ctx: Configure,
    session: SessionDep,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: datetime | None = None,
) -> UsageOut:
    return await AIService(session, ctx).usage(from_, to)

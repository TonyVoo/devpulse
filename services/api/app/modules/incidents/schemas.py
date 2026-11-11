from datetime import datetime
from typing import Annotated, Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints

from app.modules.alerts.models import Severity
from app.modules.incidents.models import (
    ActorType,
    Correlation,
    EventType,
    IncidentSource,
    IncidentStatus,
)

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=200)]
Note = Annotated[str, StringConstraints(strip_whitespace=True, max_length=4000)]


class PersonRef(BaseModel):
    id: UUID
    display_name: str


class ServiceRef(BaseModel):
    id: UUID
    name: str
    slug: str


class IncidentOut(BaseModel):
    id: UUID
    number: int
    key: str
    title: str
    summary: str | None
    severity: Severity
    status: IncidentStatus
    service: ServiceRef | None
    assignee: PersonRef | None
    escalation_level: int
    source: IncidentSource
    started_at: datetime
    acknowledged_at: datetime | None
    resolved_at: datetime | None
    resolution_note: str | None
    root_cause_confirmed: str | None
    is_demo: bool
    version: int
    updated_at: datetime


class IncidentCreateIn(BaseModel):
    title: Title
    severity: Severity
    service_id: UUID | None = None
    summary: Note | None = None


class ResolveIn(BaseModel):
    resolution_note: Note | None = None
    root_cause: Note | None = None


class AssignIn(BaseModel):
    user_id: UUID | None


class EscalateIn(BaseModel):
    reason: Note | None = None


class SeverityIn(BaseModel):
    severity: Severity


class ReopenIn(BaseModel):
    reason: Note | None = None


class EventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    type: EventType
    actor_type: ActorType
    actor: PersonRef | None
    data: dict[str, Any]
    created_at: datetime


class CommentIn(BaseModel):
    body: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=10000)]
    client_id: UUID


class CommentOut(BaseModel):
    id: UUID
    client_id: UUID
    body: str
    author: PersonRef | None
    created_at: datetime


class CorrelatedDeploymentOut(BaseModel):
    deployment_id: UUID
    version: str
    commit_sha: str | None
    commit_message: str | None
    status: str
    started_at: datetime
    correlation: Correlation
    score: float
    set_by: ActorType


class CorrelationIn(BaseModel):
    correlation: Correlation

from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from app.modules.ai.language import Language
from app.modules.ai.models import (
    EvidenceKind,
    MessageRole,
    ProposalStatus,
    Risk,
    RunStatus,
    Trigger,
)
from app.modules.ai.output import Analysis
from app.modules.alerts.models import Severity


class EvidenceOut(BaseModel):
    ref: str
    kind: EvidenceKind
    title: str
    excerpt: dict[str, Any]
    source_query: dict[str, Any]
    observed_at: datetime | None


class ProposalOut(BaseModel):
    id: UUID
    kind: str
    description: str
    risk: Risk
    status: ProposalStatus
    decided_by: UUID | None
    decided_at: datetime | None
    decision_note: str | None
    # Approval records a human decision. DevPulse never executes the action.
    executes_automatically: bool = False


class InvestigationSummary(BaseModel):
    id: UUID
    incident_id: UUID
    incident_key: str
    incident_title: str
    incident_severity: Severity
    trigger: Trigger
    status: RunStatus
    provider: str
    model: str
    # True when the analysis came from the rule-based FakeProvider, not a language model.
    is_demo_provider: bool
    language: Language
    summary: str | None
    error_code: str | None
    created_at: datetime
    finished_at: datetime | None


class InvestigationOut(InvestigationSummary):
    prompt_version: str
    result: Analysis | None
    data_gaps: list[str]
    error_detail: str | None
    evidence: list[EvidenceOut]
    proposals: list[ProposalOut]
    tool_calls_used: int
    tokens_used: int
    started_at: datetime | None
    requested_by: UUID | None
    my_feedback: bool | None


class MessageOut(BaseModel):
    id: UUID
    role: MessageRole
    content: str
    evidence_refs: list[str]
    tool_name: str | None
    author_id: UUID | None
    client_id: UUID | None
    created_at: datetime


class StartIn(BaseModel):
    # The requester's UI language; when omitted, the Accept-Language header decides.
    language: Language | None = None


class AskIn(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    client_id: UUID
    # Language of the answer; defaults to the Accept-Language header, then the run's language.
    language: Language | None = None


class AskOut(BaseModel):
    messages: list[MessageOut]  # question, tool steps, answer (in order)
    new_evidence: list[EvidenceOut]


class DecisionIn(BaseModel):
    approve: bool
    note: str | None = Field(default=None, max_length=1000)


class FeedbackIn(BaseModel):
    helpful: bool
    note: str | None = Field(default=None, max_length=1000)


class ProviderInfo(BaseModel):
    name: str
    configured: bool
    is_demo: bool


class RedactionSettings(BaseModel):
    emails: bool = True
    ips: bool = True
    secrets: bool = True


class AISettingsIn(BaseModel):
    enabled: bool
    provider: str | None = Field(default=None, max_length=32)
    model: str | None = Field(default=None, max_length=80, pattern=r"^[a-z0-9][a-z0-9._-]*$")
    monthly_budget_micros: int = Field(ge=0, le=10_000_000_000)
    max_tokens_per_run: int = Field(ge=5_000, le=2_000_000)
    auto_investigate_min_severity: Severity | None = None
    data_redaction: RedactionSettings = RedactionSettings()
    # Language of automatic analyses (no person asked for them).
    language: Language = "en"


class AISettingsOut(AISettingsIn):
    effective_provider: str
    effective_model: str
    providers: list[ProviderInfo]
    month_to_date_cost_micros: int
    version: int
    # Provider API keys are server configuration; they are never returned or accepted here.


class UsageDay(BaseModel):
    day: date
    provider: str
    model: str
    calls: int
    input_tokens: int
    output_tokens: int
    cached_tokens: int
    cost_micros: int


class UsageOut(BaseModel):
    from_: datetime
    to: datetime
    total_cost_micros: int
    month_to_date_cost_micros: int
    monthly_budget_micros: int
    days: list[UsageDay]

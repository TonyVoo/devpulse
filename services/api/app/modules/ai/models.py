"""AI investigator storage (docs/DATABASE_SCHEMA.md § AI)."""

from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk
from app.modules.alerts.models import Severity, severity_enum


def _enum(e: type[StrEnum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x], validate_strings=True)


class Trigger(StrEnum):
    AUTO = "auto"
    MANUAL = "manual"


class RunStatus(StrEnum):
    QUEUED = "queued"
    COLLECTING = "collecting"
    ANALYZING = "analyzing"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    REJECTED = "rejected"


ACTIVE_STATUSES = (RunStatus.QUEUED, RunStatus.COLLECTING, RunStatus.ANALYZING)


class EvidenceKind(StrEnum):
    METRIC = "metric"
    LOG = "log"
    DEPLOYMENT = "deployment"
    INCIDENT = "incident"
    ALERT = "alert"


class MessageRole(StrEnum):
    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


class Risk(StrEnum):
    READ_ONLY = "read_only"
    SENSITIVE = "sensitive"
    DESTRUCTIVE = "destructive"


class ProposalStatus(StrEnum):
    # There is deliberately no "executed": DevPulse records decisions, it never runs actions.
    PROPOSED = "proposed"
    APPROVED = "approved"
    REJECTED = "rejected"


class AISettings(Timestamps, Base):
    __tablename__ = "ai_settings"

    org_id: Mapped[UUID] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), primary_key=True
    )
    # Per-org opt-in: nothing is sent to a provider unless an admin enables AI.
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    provider: Mapped[str | None] = mapped_column(String(32))  # None = server default
    model: Mapped[str | None] = mapped_column(String(80))
    monthly_budget_micros: Mapped[int] = mapped_column(
        BigInteger, default=20_000_000, server_default="20000000"
    )
    max_tokens_per_run: Mapped[int] = mapped_column(
        Integer, default=200_000, server_default="200000"
    )
    # None = never investigate automatically.
    auto_investigate_min_severity: Mapped[Severity | None] = mapped_column(severity_enum)
    data_redaction: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        default=lambda: {"emails": True, "ips": True, "secrets": True},
        server_default=text("""'{"emails": true, "ips": true, "secrets": true}'::jsonb"""),
    )
    updated_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")


class AIInvestigation(UUIDPk, Timestamps, Base):
    __tablename__ = "ai_investigations"
    __table_args__ = (
        Index("ix_ai_investigations_incident", "org_id", "incident_id", "created_at"),
        Index("ix_ai_investigations_org_created", "org_id", "created_at"),
        # One active run per incident (AI_ARCHITECTURE.md §6).
        Index(
            "uq_ai_investigations_active",
            "incident_id",
            unique=True,
            postgresql_where=text("status IN ('queued', 'collecting', 'analyzing')"),
        ),
        # At most one automatic run per incident.
        Index(
            "uq_ai_investigations_auto",
            "incident_id",
            unique=True,
            postgresql_where=text("trigger = 'auto'"),
        ),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    incident_id: Mapped[UUID] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"))
    trigger: Mapped[Trigger] = mapped_column(_enum(Trigger, "ai_trigger"))
    status: Mapped[RunStatus] = mapped_column(_enum(RunStatus, "ai_run_status"))
    provider: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(80))
    prompt_version: Mapped[str] = mapped_column(String(32))
    context_hash: Mapped[str | None] = mapped_column(String(64))
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    data_gaps: Mapped[list[str]] = mapped_column(JSONB, default=list, server_default="[]")
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_detail: Mapped[str | None] = mapped_column(Text)
    tool_calls_used: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    tokens_used: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    requested_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")


class AIEvidence(UUIDPk, Base):
    __tablename__ = "ai_evidence"
    __table_args__ = (UniqueConstraint("investigation_id", "ref"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    investigation_id: Mapped[UUID] = mapped_column(
        ForeignKey("ai_investigations.id", ondelete="CASCADE")
    )
    ref: Mapped[str] = mapped_column(String(16))
    kind: Mapped[EvidenceKind] = mapped_column(_enum(EvidenceKind, "ai_evidence_kind"))
    title: Mapped[str] = mapped_column(String(200))
    # Deterministic, computed in Python from stored telemetry: the UI shows this, never a
    # number restated by the model.
    excerpt: Mapped[dict[str, Any]] = mapped_column(JSONB)
    # How it was fetched, so anyone can reproduce it.
    source_query: Mapped[dict[str, Any]] = mapped_column(JSONB)
    observed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class AIMessage(UUIDPk, Base):
    __tablename__ = "ai_messages"
    __table_args__ = (Index("ix_ai_messages_thread", "investigation_id", "created_at"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    investigation_id: Mapped[UUID] = mapped_column(
        ForeignKey("ai_investigations.id", ondelete="CASCADE")
    )
    role: Mapped[MessageRole] = mapped_column(_enum(MessageRole, "ai_message_role"))
    content: Mapped[str] = mapped_column(Text)
    evidence_refs: Mapped[list[str]] = mapped_column(JSONB, default=list, server_default="[]")
    tool_name: Mapped[str | None] = mapped_column(String(64))
    author_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # Client-generated id keeps "ask" idempotent across retries.
    client_id: Mapped[UUID | None] = mapped_column(unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class AIUsage(UUIDPk, Base):
    __tablename__ = "ai_usage"
    __table_args__ = (Index("ix_ai_usage_org_created", "org_id", "created_at"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    investigation_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("ai_investigations.id", ondelete="SET NULL")
    )
    purpose: Mapped[str] = mapped_column(String(32))  # investigate | repair | chat
    provider: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(80))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cached_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cache_write_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cost_micros: Mapped[int] = mapped_column(BigInteger, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    attempt: Mapped[int] = mapped_column(Integer, default=1)
    outcome: Mapped[str] = mapped_column(String(32))  # ok | invalid_output | error code
    request_id: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class AIActionProposal(UUIDPk, Base):
    __tablename__ = "ai_action_proposals"
    __table_args__ = (Index("ix_ai_action_proposals_inv", "investigation_id"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    investigation_id: Mapped[UUID] = mapped_column(
        ForeignKey("ai_investigations.id", ondelete="CASCADE")
    )
    kind: Mapped[str] = mapped_column(String(32))
    description: Mapped[str] = mapped_column(Text)
    risk: Mapped[Risk] = mapped_column(_enum(Risk, "ai_risk"))
    status: Mapped[ProposalStatus] = mapped_column(_enum(ProposalStatus, "ai_proposal_status"))
    decided_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decision_note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class AIFeedback(Base):
    __tablename__ = "ai_feedback"
    __table_args__ = (PrimaryKeyConstraint("investigation_id", "user_id"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    investigation_id: Mapped[UUID] = mapped_column(
        ForeignKey("ai_investigations.id", ondelete="CASCADE")
    )
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    helpful: Mapped[bool] = mapped_column(Boolean)
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

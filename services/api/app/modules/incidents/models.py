from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import (
    REAL,
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    PrimaryKeyConstraint,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk
from app.modules.alerts.models import Severity, severity_enum


class IncidentStatus(StrEnum):
    TRIGGERED = "triggered"
    ACKNOWLEDGED = "acknowledged"
    RESOLVED = "resolved"


class IncidentSource(StrEnum):
    ALERT = "alert"
    MANUAL = "manual"
    API = "api"


class EventType(StrEnum):
    CREATED = "created"
    ACKNOWLEDGED = "acknowledged"
    RESOLVED = "resolved"
    REOPENED = "reopened"
    ASSIGNED = "assigned"
    ESCALATED = "escalated"
    SEVERITY_CHANGED = "severity_changed"
    COMMENT_ADDED = "comment_added"
    ALERT_ATTACHED = "alert_attached"
    ALERT_RESOLVED = "alert_resolved"
    DEPLOYMENT_CORRELATED = "deployment_correlated"
    AI_ANALYSIS = "ai_analysis"


class ActorType(StrEnum):
    USER = "user"
    SYSTEM = "system"
    AI = "ai"


class Correlation(StrEnum):
    SUSPECTED = "suspected"
    RULED_OUT = "ruled_out"
    CONFIRMED = "confirmed"


def _enum(e: type[StrEnum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x], validate_strings=True)


actor_type_enum = _enum(ActorType, "incident_actor_type")


class Incident(UUIDPk, Timestamps, Base):
    __tablename__ = "incidents"
    __table_args__ = (
        UniqueConstraint("org_id", "number"),
        Index("ix_incidents_org_status_started", "org_id", "status", "started_at"),
        Index("ix_incidents_org_started", "org_id", "started_at", "id"),
        Index("ix_incidents_sync", "org_id", "change_seq"),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    number: Mapped[int] = mapped_column(BigInteger)
    title: Mapped[str] = mapped_column(String(200))
    summary: Mapped[str | None] = mapped_column(Text)
    severity: Mapped[Severity] = mapped_column(severity_enum)
    status: Mapped[IncidentStatus] = mapped_column(_enum(IncidentStatus, "incident_status"))
    service_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("services.id", ondelete="SET NULL"), index=True
    )
    assignee_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    escalation_level: Mapped[int] = mapped_column(SmallInteger, default=0, server_default="0")
    source: Mapped[IncidentSource] = mapped_column(_enum(IncidentSource, "incident_source"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolution_note: Mapped[str | None] = mapped_column(Text)
    # Set by humans only; AI analyses never write this (AI_ARCHITECTURE.md §2).
    root_cause_confirmed: Mapped[str | None] = mapped_column(Text)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    # Set by the sync trigger (ADR-019); never written by the application.
    change_seq: Mapped[int] = mapped_column(BigInteger, server_default="0", index=False)

    @property
    def key(self) -> str:
        return f"INC-{self.number}"


class IncidentEvent(UUIDPk, Base):
    """Append-only timeline entry."""

    __tablename__ = "incident_events"
    __table_args__ = (Index("ix_incident_events_timeline", "org_id", "incident_id", "created_at"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    incident_id: Mapped[UUID] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"))
    type: Mapped[EventType] = mapped_column(_enum(EventType, "incident_event_type"))
    actor_type: Mapped[ActorType] = mapped_column(actor_type_enum)
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    data: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class IncidentComment(UUIDPk, Base):
    __tablename__ = "incident_comments"
    __table_args__ = (Index("ix_incident_comments_thread", "org_id", "incident_id", "created_at"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    incident_id: Mapped[UUID] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"))
    author_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    body: Mapped[str] = mapped_column(Text)
    # Client-generated id makes offline posting idempotent.
    client_id: Mapped[UUID] = mapped_column(unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class IncidentDeployment(Base):
    __tablename__ = "incident_deployments"
    __table_args__ = (PrimaryKeyConstraint("incident_id", "deployment_id"),)

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    incident_id: Mapped[UUID] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"))
    deployment_id: Mapped[UUID] = mapped_column(ForeignKey("deployments.id", ondelete="CASCADE"))
    correlation: Mapped[Correlation] = mapped_column(_enum(Correlation, "deployment_correlation"))
    score: Mapped[float] = mapped_column(REAL)
    set_by: Mapped[ActorType] = mapped_column(actor_type_enum)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class IdempotencyKey(Base):
    """Stored response for an `Idempotency-Key` (24h). Replays return the same response."""

    __tablename__ = "idempotency_keys"
    __table_args__ = (PrimaryKeyConstraint("user_id", "key"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    key: Mapped[str] = mapped_column(String(80))
    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    fingerprint: Mapped[str] = mapped_column(String(64))
    status_code: Mapped[int] = mapped_column(SmallInteger)
    response: Mapped[dict[str, Any]] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

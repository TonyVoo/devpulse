from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Double,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk


class Severity(StrEnum):
    SEV1 = "sev1"
    SEV2 = "sev2"
    SEV3 = "sev3"
    SEV4 = "sev4"


class Aggregation(StrEnum):
    AVG = "avg"
    SUM = "sum"
    MIN = "min"
    MAX = "max"
    P95 = "p95"
    P99 = "p99"
    # Only meaningful for the derived metric `http.server.error_rate`.
    RATIO = "ratio"


class Comparator(StrEnum):
    GT = "gt"
    GTE = "gte"
    LT = "lt"
    LTE = "lte"


class AlertState(StrEnum):
    PENDING = "pending"
    FIRING = "firing"
    RESOLVED = "resolved"


def _enum(e: type[StrEnum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x], validate_strings=True)


severity_enum = _enum(Severity, "severity")


class AlertRule(UUIDPk, Timestamps, Base):
    __tablename__ = "alert_rules"
    __table_args__ = (
        CheckConstraint("window_s BETWEEN 60 AND 3600", name="window_range"),
        CheckConstraint("for_s BETWEEN 0 AND 3600", name="for_range"),
        Index("ix_alert_rules_org_enabled", "org_id", "enabled"),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    service_id: Mapped[UUID] = mapped_column(ForeignKey("services.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(120))
    metric: Mapped[str] = mapped_column(String(120))
    aggregation: Mapped[Aggregation] = mapped_column(_enum(Aggregation, "alert_aggregation"))
    comparator: Mapped[Comparator] = mapped_column(_enum(Comparator, "alert_comparator"))
    threshold: Mapped[float] = mapped_column(Double)
    window_s: Mapped[int] = mapped_column(Integer, default=300)
    for_s: Mapped[int] = mapped_column(Integer, default=0)
    severity: Mapped[Severity] = mapped_column(severity_enum)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    created_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")


class AlertInstance(UUIDPk, Base):
    """One episode of a rule breaching for a service: pending → firing → resolved."""

    __tablename__ = "alert_instances"
    __table_args__ = (
        Index(
            "uq_alert_instances_open",
            "rule_id",
            unique=True,
            postgresql_where=text("state <> 'resolved'"),
        ),
        Index("ix_alert_instances_org_state", "org_id", "state"),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    rule_id: Mapped[UUID] = mapped_column(ForeignKey("alert_rules.id", ondelete="CASCADE"))
    service_id: Mapped[UUID] = mapped_column(ForeignKey("services.id", ondelete="CASCADE"))
    state: Mapped[AlertState] = mapped_column(_enum(AlertState, "alert_state"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    fired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_value: Mapped[float | None] = mapped_column(Double)
    last_evaluated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    incident_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("incidents.id", ondelete="SET NULL")
    )

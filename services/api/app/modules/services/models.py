from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from sqlalchemy import (
    ARRAY,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk


class Health(StrEnum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    CRITICAL = "critical"
    UNKNOWN = "unknown"


class Tier(StrEnum):
    CRITICAL = "critical"
    HIGH = "high"
    LOW = "low"


def _enum(e: type[StrEnum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x], validate_strings=True)


class Service(UUIDPk, Timestamps, Base):
    __tablename__ = "services"
    __table_args__ = (
        UniqueConstraint("org_id", "environment", "slug"),
        Index("ix_services_org_health", "org_id", "health"),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    slug: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    environment: Mapped[str] = mapped_column(String(32), default="production")
    tier: Mapped[Tier] = mapped_column(_enum(Tier, "service_tier"), default=Tier.HIGH)
    owner_team: Mapped[str | None] = mapped_column(String(80))
    repo_url: Mapped[str | None] = mapped_column(String(512))
    health: Mapped[Health] = mapped_column(
        _enum(Health, "service_health"), default=Health.UNKNOWN, server_default="unknown"
    )
    health_changed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    tags: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict, server_default="{}")
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class IngestKey(UUIDPk, Base):
    """Credential for telemetry/deployment ingestion. Resolves to exactly one org (and
    optionally one service) server-side; payloads cannot choose their org."""

    __tablename__ = "ingest_keys"

    org_id: Mapped[UUID] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    service_id: Mapped[UUID | None] = mapped_column(ForeignKey("services.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(80))
    prefix: Mapped[str] = mapped_column(String(24))
    key_hash: Mapped[str] = mapped_column(String(64), unique=True)
    scopes: Mapped[list[str]] = mapped_column(ARRAY(String(40)))
    # Telemetry sent with a demo key is flagged is_demo; real keys can never set it.
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

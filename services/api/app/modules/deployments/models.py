from datetime import datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk


class DeployStatus(StrEnum):
    STARTED = "started"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    ROLLED_BACK = "rolled_back"


class BuildStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class DeploySource(StrEnum):
    GITHUB = "github"
    API = "api"
    MANUAL = "manual"


def _enum(e: type[StrEnum], name: str) -> Enum:
    return Enum(e, name=name, values_callable=lambda x: [m.value for m in x], validate_strings=True)


class Deployment(UUIDPk, Timestamps, Base):
    __tablename__ = "deployments"
    __table_args__ = (
        UniqueConstraint("org_id", "source", "external_id"),
        Index("ix_deployments_service_started", "org_id", "service_id", "started_at"),
        Index("ix_deployments_org_started", "org_id", "started_at", "id"),
    )

    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    service_id: Mapped[UUID] = mapped_column(ForeignKey("services.id", ondelete="CASCADE"))
    environment: Mapped[str] = mapped_column(String(32))
    version: Mapped[str] = mapped_column(String(80))
    commit_sha: Mapped[str | None] = mapped_column(String(64))
    commit_message: Mapped[str | None] = mapped_column(Text)
    commit_author: Mapped[str | None] = mapped_column(String(120))
    branch: Mapped[str | None] = mapped_column(String(200))
    repo_url: Mapped[str | None] = mapped_column(String(512))
    build_status: Mapped[BuildStatus | None] = mapped_column(_enum(BuildStatus, "build_status"))
    status: Mapped[DeployStatus] = mapped_column(_enum(DeployStatus, "deploy_status"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    source: Mapped[DeploySource] = mapped_column(_enum(DeploySource, "deploy_source"))
    external_id: Mapped[str] = mapped_column(String(120))
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")

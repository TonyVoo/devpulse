from uuid import UUID

from sqlalchemy import Boolean, ForeignKey, PrimaryKeyConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps
from app.modules.alerts.models import Severity, severity_enum


class NotificationPreference(Timestamps, Base):
    """Per user, per org push preferences. Absent row = defaults (push on, sev2 and worse)."""

    __tablename__ = "notification_preferences"
    __table_args__ = (PrimaryKeyConstraint("user_id", "org_id"),)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    org_id: Mapped[UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    # Notify for incidents at this severity or worse (sev1 is the worst).
    min_severity: Mapped[Severity] = mapped_column(severity_enum, default=Severity.SEV2)
    only_assigned: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")

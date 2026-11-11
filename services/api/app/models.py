"""Imports every ORM model so `Base.metadata` is complete (Alembic, tests)."""

from app.core.db import Base
from app.modules.audit.models import AuditLog
from app.modules.auth.models import RefreshToken
from app.modules.organizations.models import Invitation, Membership, Organization
from app.modules.users.models import Device, User

__all__ = [
    "AuditLog",
    "Base",
    "Device",
    "Invitation",
    "Membership",
    "Organization",
    "RefreshToken",
    "User",
]

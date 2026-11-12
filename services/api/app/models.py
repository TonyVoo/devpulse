"""Imports every ORM model so `Base.metadata` is complete (Alembic, tests)."""

from app.core.db import Base
from app.modules.ai.models import (
    AIActionProposal,
    AIEvidence,
    AIFeedback,
    AIInvestigation,
    AIMessage,
    AISettings,
    AIUsage,
)
from app.modules.alerts.models import AlertInstance, AlertRule
from app.modules.audit.models import AuditLog
from app.modules.auth.models import RefreshToken
from app.modules.deployments.models import Deployment
from app.modules.incidents.models import (
    IdempotencyKey,
    Incident,
    IncidentComment,
    IncidentDeployment,
    IncidentEvent,
)
from app.modules.integrations.models import Integration, WebhookDelivery
from app.modules.notifications.models import NotificationPreference
from app.modules.organizations.models import Invitation, Membership, Organization
from app.modules.realtime.models import OutboxEvent
from app.modules.services.models import IngestKey, Service
from app.modules.telemetry.models import log_events, metric_points, metric_rollups_1m
from app.modules.users.models import Device, User

__all__ = [
    "AIActionProposal",
    "AIEvidence",
    "AIFeedback",
    "AIInvestigation",
    "AIMessage",
    "AISettings",
    "AIUsage",
    "AlertInstance",
    "AlertRule",
    "AuditLog",
    "Base",
    "Deployment",
    "Device",
    "IdempotencyKey",
    "Incident",
    "IncidentComment",
    "IncidentDeployment",
    "IncidentEvent",
    "IngestKey",
    "Integration",
    "Invitation",
    "Membership",
    "NotificationPreference",
    "Organization",
    "OutboxEvent",
    "RefreshToken",
    "Service",
    "User",
    "WebhookDelivery",
    "log_events",
    "metric_points",
    "metric_rollups_1m",
]

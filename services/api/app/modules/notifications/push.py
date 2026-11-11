"""Push notifications for incident events.

The relay calls `dispatch_incident_event` for each `incident_event` outbox row. Recipients:
org members with a registered device whose preferences match (push enabled, severity at or
above their threshold, "only assigned" respected). The actor never notifies themselves.

Delivery goes through a `PushProvider`. Real FCM delivery needs a Firebase project and
service account (not configured yet); until then `LoggingPushProvider` records what would
have been sent so the whole path can be exercised end to end.
"""

from dataclasses import dataclass, field
from typing import Any, Protocol
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.alerts.models import Severity
from app.modules.incidents.models import Incident
from app.modules.notifications.models import NotificationPreference
from app.modules.organizations.models import Membership
from app.modules.users.models import Device

log = structlog.get_logger(__name__)

NOTIFY_EVENTS = {"created", "escalated", "reopened", "assigned"}
_SEV_RANK = {Severity.SEV1: 1, Severity.SEV2: 2, Severity.SEV3: 3, Severity.SEV4: 4}


@dataclass(frozen=True)
class PushMessage:
    tokens: list[str]
    title: str
    body: str
    data: dict[str, str]


class PushProvider(Protocol):
    async def send(self, message: PushMessage) -> None: ...


class LoggingPushProvider:
    """Default until FCM credentials exist: logs instead of sending."""

    async def send(self, message: PushMessage) -> None:
        log.info(
            "push_not_sent_no_provider",
            devices=len(message.tokens),
            title=message.title,
            route=message.data.get("route"),
        )


@dataclass
class RecordingPushProvider:
    """For tests."""

    sent: list[PushMessage] = field(default_factory=list)

    async def send(self, message: PushMessage) -> None:
        self.sent.append(message)


def _title(event: str, inc: Incident) -> str:
    prefix = f"[{inc.severity.value.upper()}] {inc.key}"
    return {
        "created": f"{prefix} opened",
        "escalated": f"{prefix} escalated (level {inc.escalation_level})",
        "reopened": f"{prefix} reopened",
        "assigned": f"{prefix} assigned to you",
    }[event]


async def dispatch_incident_event(
    session: AsyncSession, provider: PushProvider, org_id: UUID, payload: dict[str, Any]
) -> int:
    """Returns the number of devices targeted."""
    event = str(payload.get("type"))
    if event not in NOTIFY_EVENTS:
        return 0
    inc = await session.scalar(
        select(Incident).where(
            Incident.org_id == org_id, Incident.id == UUID(payload["incident_id"])
        )
    )
    if inc is None:
        return 0
    actor = payload.get("actor_id")

    rows = (
        await session.execute(
            select(Membership.user_id, NotificationPreference)
            .outerjoin(
                NotificationPreference,
                (NotificationPreference.user_id == Membership.user_id)
                & (NotificationPreference.org_id == Membership.org_id),
            )
            .where(Membership.org_id == org_id)
        )
    ).all()
    recipients: list[UUID] = []
    for user_id, pref in rows:
        if actor and str(user_id) == str(actor):
            continue
        enabled = pref.push_enabled if pref else True
        threshold = pref.min_severity if pref else Severity.SEV2
        only_assigned = pref.only_assigned if pref else False
        if not enabled:
            continue
        if event == "assigned":
            if inc.assignee_id != user_id:
                continue
        elif _SEV_RANK[inc.severity] > _SEV_RANK[threshold] or (
            only_assigned and inc.assignee_id != user_id
        ):
            continue
        recipients.append(user_id)
    if not recipients:
        return 0

    tokens = list(
        (
            await session.scalars(select(Device.fcm_token).where(Device.user_id.in_(recipients)))
        ).all()
    )
    if not tokens:
        return 0
    await provider.send(
        PushMessage(
            tokens=tokens,
            title=_title(event, inc),
            body=inc.title,
            data={
                # The app routes on `route` (cold start and background taps).
                "route": f"/incidents/{inc.key}",
                "org_id": str(org_id),
                "incident_id": str(inc.id),
                "severity": inc.severity.value,
                "version": str(inc.version),
            },
        )
    )
    return len(tokens)

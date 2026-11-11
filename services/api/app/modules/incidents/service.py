"""Incident lifecycle (state machine), timeline, comments and deployment correlation."""

import re
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import Select, and_, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.errors import Conflict, NotFound, Unprocessable
from app.core.pagination import MAX_LIMIT, Page, decode_cursor, encode_cursor
from app.core.tenancy import OrgContext, OrgScopedRepository
from app.modules.alerts.models import Severity
from app.modules.deployments.models import Deployment
from app.modules.incidents.models import (
    ActorType,
    Correlation,
    EventType,
    Incident,
    IncidentComment,
    IncidentDeployment,
    IncidentEvent,
    IncidentSource,
    IncidentStatus,
)
from app.modules.incidents.schemas import (
    CommentOut,
    CorrelatedDeploymentOut,
    EventOut,
    IncidentOut,
    PersonRef,
    ServiceRef,
)
from app.modules.organizations.models import Membership, Organization
from app.modules.services.models import Service
from app.modules.services.service import check_version
from app.modules.users.models import User

CORRELATION_LOOKBACK = timedelta(hours=2)
CORRELATION_LOOKAHEAD = timedelta(minutes=5)
MAX_ESCALATION = 5
_KEY = re.compile(r"^INC-(\d{1,12})$", re.IGNORECASE)

Assignee = aliased(User)


def _now() -> datetime:
    return datetime.now(UTC)


def _invalid(action: str, status: IncidentStatus) -> Conflict:
    return Conflict(
        f"Can't {action} an incident that is {status.value}",
        code="incident.invalid_transition",
        extra={"current_status": status.value},
    )


def _row_to_out(
    inc: Incident, svc_name: str | None, svc_slug: str | None, assignee: str | None
) -> IncidentOut:
    return IncidentOut(
        id=inc.id,
        number=inc.number,
        key=inc.key,
        title=inc.title,
        summary=inc.summary,
        severity=inc.severity,
        status=inc.status,
        service=ServiceRef(id=inc.service_id, name=svc_name or "", slug=svc_slug or "")
        if inc.service_id
        else None,
        assignee=PersonRef(id=inc.assignee_id, display_name=assignee or "")
        if inc.assignee_id
        else None,
        escalation_level=inc.escalation_level,
        source=inc.source,
        started_at=inc.started_at,
        acknowledged_at=inc.acknowledged_at,
        resolved_at=inc.resolved_at,
        resolution_note=inc.resolution_note,
        root_cause_confirmed=inc.root_cause_confirmed,
        is_demo=inc.is_demo,
        version=inc.version,
        updated_at=inc.updated_at,
    )


def add_event(
    session: AsyncSession,
    inc: Incident,
    type_: EventType,
    *,
    actor_type: ActorType = ActorType.USER,
    actor_id: UUID | None = None,
    data: dict[str, Any] | None = None,
) -> None:
    session.add(
        IncidentEvent(
            org_id=inc.org_id,
            incident_id=inc.id,
            type=type_,
            actor_type=actor_type,
            actor_id=actor_id,
            data=data or {},
        )
    )


async def create_incident(
    session: AsyncSession,
    *,
    org_id: UUID,
    title: str,
    severity: Severity,
    source: IncidentSource,
    service_id: UUID | None,
    started_at: datetime | None = None,
    summary: str | None = None,
    actor_id: UUID | None = None,
    is_demo: bool = False,
    event_data: dict[str, Any] | None = None,
) -> Incident:
    """Opens an incident (caller commits). Allocates the per-org number under a row lock."""
    number = (
        await session.execute(
            update(Organization)
            .where(Organization.id == org_id)
            .values(incident_seq=Organization.incident_seq + 1)
            .returning(Organization.incident_seq)
        )
    ).scalar_one()
    inc = Incident(
        org_id=org_id,
        number=number,
        title=title,
        summary=summary,
        severity=severity,
        status=IncidentStatus.TRIGGERED,
        service_id=service_id,
        source=source,
        started_at=started_at or _now(),
        is_demo=is_demo,
    )
    session.add(inc)
    await session.flush()
    add_event(
        session,
        inc,
        EventType.CREATED,
        actor_type=ActorType.USER if actor_id else ActorType.SYSTEM,
        actor_id=actor_id,
        data={"severity": severity.value, "source": source.value, **(event_data or {})},
    )
    await correlate_deployments(session, inc)
    return inc


async def correlate_deployments(session: AsyncSession, inc: Incident) -> int:
    """Suspect deployments of the same service shortly before the incident started.
    Score decays linearly with time since the deploy; failed/rolled-back deploys weigh more.
    This is a heuristic signal for humans (and later the AI), never a conclusion."""
    if inc.service_id is None:
        return 0
    deps = (
        await session.scalars(
            select(Deployment)
            .where(
                Deployment.org_id == inc.org_id,
                Deployment.service_id == inc.service_id,
                Deployment.started_at >= inc.started_at - CORRELATION_LOOKBACK,
                Deployment.started_at <= inc.started_at + CORRELATION_LOOKAHEAD,
            )
            .order_by(Deployment.started_at.desc())
            .limit(3)
        )
    ).all()
    for dep in deps:
        age = max((inc.started_at - dep.started_at).total_seconds(), 0.0)
        score = max(0.05, 1 - age / CORRELATION_LOOKBACK.total_seconds())
        if dep.status.value in ("failed", "rolled_back"):
            score = min(1.0, score + 0.15)
        session.add(
            IncidentDeployment(
                org_id=inc.org_id,
                incident_id=inc.id,
                deployment_id=dep.id,
                correlation=Correlation.SUSPECTED,
                score=round(score, 3),
                set_by=ActorType.SYSTEM,
            )
        )
        add_event(
            session,
            inc,
            EventType.DEPLOYMENT_CORRELATED,
            actor_type=ActorType.SYSTEM,
            data={"deployment_id": str(dep.id), "version": dep.version, "score": round(score, 3)},
        )
    return len(deps)


class IncidentService(OrgScopedRepository):
    def __init__(self, session: AsyncSession, ctx: OrgContext) -> None:
        super().__init__(session, ctx)

    # ------------------------------------------------------------------ reads

    def _base(self) -> Select[Incident, str, str, str]:
        return (
            select(Incident, Service.name, Service.slug, Assignee.display_name)
            .outerjoin(Service, Service.id == Incident.service_id)
            .outerjoin(Assignee, Assignee.id == Incident.assignee_id)
            .where(Incident.org_id == self.ctx.org_id)
        )

    async def _load(self, ref: str, *, lock: bool = False) -> Incident:
        m = _KEY.match(ref)
        stmt = self.select(Incident)
        if m:
            stmt = stmt.where(Incident.number == int(m.group(1)))
        else:
            try:
                stmt = stmt.where(Incident.id == UUID(ref))
            except ValueError as e:
                raise NotFound("Incident not found", code="incident.not_found") from e
        if lock:
            stmt = stmt.with_for_update()
        inc = await self.session.scalar(stmt)
        if inc is None:
            raise NotFound("Incident not found", code="incident.not_found")
        return inc

    async def out(self, inc_id: UUID) -> IncidentOut:
        row = (await self.session.execute(self._base().where(Incident.id == inc_id))).one()
        return _row_to_out(*row)

    async def get(self, ref: str) -> IncidentOut:
        inc = await self._load(ref)
        return await self.out(inc.id)

    async def page(
        self,
        *,
        limit: int,
        cursor: str | None,
        status: list[IncidentStatus] | None,
        severity: list[Severity] | None,
        service_id: UUID | None,
        assignee: str | None,
        q: str | None,
    ) -> Page[IncidentOut]:
        limit = max(1, min(limit, MAX_LIMIT))
        stmt = self._base()
        if status:
            stmt = stmt.where(Incident.status.in_(status))
        if severity:
            stmt = stmt.where(Incident.severity.in_(severity))
        if service_id:
            stmt = stmt.where(Incident.service_id == service_id)
        if assignee == "me":
            stmt = stmt.where(Incident.assignee_id == self.ctx.user_id)
        elif assignee == "none":
            stmt = stmt.where(Incident.assignee_id.is_(None))
        if q:
            like = f"%{q.strip()[:80]}%"
            m = _KEY.match(q.strip())
            stmt = stmt.where(
                or_(Incident.title.ilike(like), Incident.number == int(m.group(1)))
                if m
                else Incident.title.ilike(like)
            )
        if cursor:
            ts, last_id = decode_cursor(cursor)
            stmt = stmt.where(
                or_(
                    Incident.started_at < ts, and_(Incident.started_at == ts, Incident.id < last_id)
                )
            )
        rows = (
            await self.session.execute(
                stmt.order_by(Incident.started_at.desc(), Incident.id.desc()).limit(limit + 1)
            )
        ).all()
        items = [_row_to_out(*r) for r in rows[:limit]]
        nxt = encode_cursor(items[-1].started_at, items[-1].id) if len(rows) > limit else None
        return Page(items=items, next_cursor=nxt)

    async def timeline(self, ref: str, *, limit: int, cursor: str | None) -> Page[EventOut]:
        inc = await self._load(ref)
        stmt = (
            select(IncidentEvent, User.display_name)
            .outerjoin(User, User.id == IncidentEvent.actor_id)
            .where(IncidentEvent.org_id == self.ctx.org_id, IncidentEvent.incident_id == inc.id)
        )
        if cursor:
            ts, last_id = decode_cursor(cursor)
            stmt = stmt.where(
                or_(
                    IncidentEvent.created_at > ts,
                    and_(IncidentEvent.created_at == ts, IncidentEvent.id > last_id),
                )
            )
        rows = (
            await self.session.execute(
                stmt.order_by(IncidentEvent.created_at, IncidentEvent.id).limit(limit + 1)
            )
        ).all()
        items = [
            EventOut(
                id=e.id,
                type=e.type,
                actor_type=e.actor_type,
                actor=PersonRef(id=e.actor_id, display_name=name or "") if e.actor_id else None,
                data=e.data,
                created_at=e.created_at,
            )
            for e, name in rows[:limit]
        ]
        nxt = encode_cursor(items[-1].created_at, items[-1].id) if len(rows) > limit else None
        return Page(items=items, next_cursor=nxt)

    async def deployments(self, ref: str) -> list[CorrelatedDeploymentOut]:
        inc = await self._load(ref)
        rows = (
            await self.session.execute(
                select(IncidentDeployment, Deployment)
                .join(Deployment, Deployment.id == IncidentDeployment.deployment_id)
                .where(
                    IncidentDeployment.org_id == self.ctx.org_id,
                    IncidentDeployment.incident_id == inc.id,
                )
                .order_by(IncidentDeployment.score.desc())
            )
        ).all()
        return [
            CorrelatedDeploymentOut(
                deployment_id=d.id,
                version=d.version,
                commit_sha=d.commit_sha,
                commit_message=d.commit_message,
                status=d.status.value,
                started_at=d.started_at,
                correlation=link.correlation,
                score=link.score,
                set_by=link.set_by,
            )
            for link, d in rows
        ]

    # --------------------------------------------------------------- commands
    # Each command locks the row, checks the version and state, writes a timeline event
    # and bumps `version`. Callers commit (via run_idempotent).

    async def create(
        self, *, title: str, severity: Severity, service_id: UUID | None, summary: str | None
    ) -> IncidentOut:
        if service_id is not None:
            exists = await self.session.scalar(
                self.select(Service).where(Service.id == service_id, Service.deleted_at.is_(None))
            )
            if exists is None:
                raise Unprocessable("Unknown service", code="service.not_found")
        inc = await create_incident(
            self.session,
            org_id=self.ctx.org_id,
            title=title,
            severity=severity,
            source=IncidentSource.MANUAL,
            service_id=service_id,
            summary=summary,
            actor_id=self.ctx.user_id,
        )
        await self.session.flush()
        return await self.out(inc.id)

    async def _command(self, ref: str, if_match: str | None) -> Incident:
        inc = await self._load(ref, lock=True)
        check_version(inc.version, if_match)
        return inc

    async def _done(
        self, inc: Incident, type_: EventType, data: dict[str, Any] | None = None
    ) -> IncidentOut:
        inc.version += 1
        add_event(self.session, inc, type_, actor_id=self.ctx.user_id, data=data)
        await self.session.flush()
        await self.session.refresh(inc)
        return await self.out(inc.id)

    async def acknowledge(self, ref: str, if_match: str | None) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status != IncidentStatus.TRIGGERED:
            raise _invalid("acknowledge", inc.status)
        inc.status = IncidentStatus.ACKNOWLEDGED
        inc.acknowledged_at = _now()
        if inc.assignee_id is None:
            inc.assignee_id = self.ctx.user_id  # acknowledging takes ownership
        return await self._done(inc, EventType.ACKNOWLEDGED)

    async def resolve(
        self, ref: str, if_match: str | None, note: str | None, root_cause: str | None
    ) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status == IncidentStatus.RESOLVED:
            raise _invalid("resolve", inc.status)
        inc.status = IncidentStatus.RESOLVED
        inc.resolved_at = _now()
        inc.resolution_note = note
        if root_cause:
            inc.root_cause_confirmed = root_cause
        return await self._done(inc, EventType.RESOLVED, {"note": note, "root_cause": root_cause})

    async def reopen(self, ref: str, if_match: str | None, reason: str | None) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status != IncidentStatus.RESOLVED:
            raise _invalid("reopen", inc.status)
        inc.status = IncidentStatus.TRIGGERED
        inc.resolved_at = None
        inc.acknowledged_at = None
        return await self._done(inc, EventType.REOPENED, {"reason": reason})

    async def assign(self, ref: str, if_match: str | None, user_id: UUID | None) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status == IncidentStatus.RESOLVED:
            raise _invalid("assign", inc.status)
        name = None
        if user_id is not None:
            row = (
                await self.session.execute(
                    select(User.display_name)
                    .join(Membership, Membership.user_id == User.id)
                    .where(Membership.org_id == self.ctx.org_id, User.id == user_id)
                )
            ).first()
            if row is None:
                raise Unprocessable(
                    "Assignee must be a member of this organization",
                    code="incident.assignee_not_member",
                )
            name = row[0]
        inc.assignee_id = user_id
        return await self._done(
            inc,
            EventType.ASSIGNED,
            {"assignee_id": str(user_id) if user_id else None, "assignee_name": name},
        )

    async def escalate(self, ref: str, if_match: str | None, reason: str | None) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status == IncidentStatus.RESOLVED:
            raise _invalid("escalate", inc.status)
        if inc.escalation_level >= MAX_ESCALATION:
            raise Conflict(
                "Already at the highest escalation level", code="incident.max_escalation"
            )
        inc.escalation_level += 1
        return await self._done(
            inc, EventType.ESCALATED, {"level": inc.escalation_level, "reason": reason}
        )

    async def set_severity(self, ref: str, if_match: str | None, severity: Severity) -> IncidentOut:
        inc = await self._command(ref, if_match)
        if inc.status == IncidentStatus.RESOLVED:
            raise _invalid("change severity of", inc.status)
        if inc.severity == severity:
            return await self.out(inc.id)
        before = inc.severity
        inc.severity = severity
        return await self._done(
            inc, EventType.SEVERITY_CHANGED, {"from": before.value, "to": severity.value}
        )

    async def set_correlation(
        self, ref: str, deployment_id: UUID, correlation: Correlation
    ) -> CorrelatedDeploymentOut:
        inc = await self._load(ref)
        dep = await self.session.scalar(
            self.select(Deployment).where(Deployment.id == deployment_id)
        )
        if dep is None:
            raise NotFound("Deployment not found", code="deployment.not_found")
        link = await self.session.get(IncidentDeployment, (inc.id, dep.id))
        if link is None:
            link = IncidentDeployment(
                org_id=self.ctx.org_id,
                incident_id=inc.id,
                deployment_id=dep.id,
                correlation=correlation,
                score=1.0,
                set_by=ActorType.USER,
            )
            self.session.add(link)
        else:
            link.correlation = correlation
            link.set_by = ActorType.USER
        add_event(
            self.session,
            inc,
            EventType.DEPLOYMENT_CORRELATED,
            actor_id=self.ctx.user_id,
            data={
                "deployment_id": str(dep.id),
                "version": dep.version,
                "correlation": correlation.value,
            },
        )
        await self.session.commit()
        return CorrelatedDeploymentOut(
            deployment_id=dep.id,
            version=dep.version,
            commit_sha=dep.commit_sha,
            commit_message=dep.commit_message,
            status=dep.status.value,
            started_at=dep.started_at,
            correlation=link.correlation,
            score=link.score,
            set_by=link.set_by,
        )

    # --------------------------------------------------------------- comments

    async def comments(self, ref: str, *, limit: int, cursor: str | None) -> Page[CommentOut]:
        inc = await self._load(ref)
        stmt = (
            select(IncidentComment, User.display_name)
            .outerjoin(User, User.id == IncidentComment.author_id)
            .where(IncidentComment.org_id == self.ctx.org_id, IncidentComment.incident_id == inc.id)
        )
        if cursor:
            ts, last_id = decode_cursor(cursor)
            stmt = stmt.where(
                or_(
                    IncidentComment.created_at > ts,
                    and_(IncidentComment.created_at == ts, IncidentComment.id > last_id),
                )
            )
        rows = (
            await self.session.execute(
                stmt.order_by(IncidentComment.created_at, IncidentComment.id).limit(limit + 1)
            )
        ).all()
        items = [self._comment_out(c, name) for c, name in rows[:limit]]
        nxt = encode_cursor(items[-1].created_at, items[-1].id) if len(rows) > limit else None
        return Page(items=items, next_cursor=nxt)

    @staticmethod
    def _comment_out(c: IncidentComment, author: str | None) -> CommentOut:
        return CommentOut(
            id=c.id,
            client_id=c.client_id,
            body=c.body,
            created_at=c.created_at,
            author=PersonRef(id=c.author_id, display_name=author or "") if c.author_id else None,
        )

    async def add_comment(self, ref: str, body: str, client_id: UUID) -> tuple[CommentOut, bool]:
        """Returns (comment, created). Re-sending the same client_id returns the original."""
        inc = await self._load(ref)
        existing = await self.session.scalar(
            select(IncidentComment).where(IncidentComment.client_id == client_id)
        )
        if existing is not None:
            if existing.org_id != self.ctx.org_id or existing.incident_id != inc.id:
                raise Conflict("client_id already used", code="comment.client_id_conflict")
            return self._comment_out(existing, None), False
        comment = IncidentComment(
            org_id=self.ctx.org_id,
            incident_id=inc.id,
            author_id=self.ctx.user_id,
            body=body,
            client_id=client_id,
        )
        self.session.add(comment)
        try:
            await self.session.flush()
        except IntegrityError as e:
            await self.session.rollback()
            raise Conflict("Duplicate comment, retry", code="comment.duplicate") from e
        add_event(
            self.session,
            inc,
            EventType.COMMENT_ADDED,
            actor_id=self.ctx.user_id,
            data={"comment_id": str(comment.id), "excerpt": body[:140]},
        )
        await self.session.commit()
        await self.session.refresh(comment)
        author = await self.session.scalar(
            select(User.display_name).where(User.id == self.ctx.user_id)
        )
        return self._comment_out(comment, author), True

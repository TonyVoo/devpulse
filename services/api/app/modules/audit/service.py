"""Audit trail. `record()` adds to the caller's transaction so the audit row commits
atomically with the change it describes."""

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict
from sqlalchemy import and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import RequestMeta
from app.core.pagination import MAX_LIMIT, Page, decode_cursor, encode_cursor
from app.core.tenancy import OrgContext, OrgScopedRepository
from app.modules.audit.models import AuditLog


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    actor_id: UUID | None
    actor_type: str
    action: str
    target_type: str
    target_id: str | None
    before: dict[str, Any] | None
    after: dict[str, Any] | None
    ip: str | None
    request_id: str | None
    created_at: datetime


def record(
    session: AsyncSession,
    *,
    org_id: UUID,
    actor_id: UUID | None,
    action: str,
    target_type: str,
    target_id: UUID | str | None = None,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
    meta: RequestMeta | None = None,
    actor_type: str = "user",
) -> None:
    session.add(
        AuditLog(
            org_id=org_id,
            actor_id=actor_id,
            actor_type=actor_type,
            action=action,
            target_type=target_type,
            target_id=str(target_id) if target_id is not None else None,
            before=before,
            after=after,
            ip=meta.ip if meta else None,
            user_agent=meta.user_agent if meta else None,
            request_id=meta.request_id if meta else None,
        )
    )


class AuditRepository(OrgScopedRepository):
    async def list(
        self, *, limit: int, cursor: str | None, action: str | None
    ) -> Page[AuditLogOut]:
        limit = max(1, min(limit, MAX_LIMIT))
        stmt = self.select(AuditLog).order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        if action:
            stmt = stmt.where(AuditLog.action == action)
        if cursor:
            ts, id_ = decode_cursor(cursor)
            stmt = stmt.where(
                or_(AuditLog.created_at < ts, and_(AuditLog.created_at == ts, AuditLog.id < id_))
            )
        rows = list((await self.session.scalars(stmt.limit(limit + 1))).all())
        next_cursor = (
            encode_cursor(rows[limit - 1].created_at, rows[limit - 1].id)
            if len(rows) > limit
            else None
        )
        return Page(
            items=[AuditLogOut.model_validate(r) for r in rows[:limit]], next_cursor=next_cursor
        )


def audit_repo(session: AsyncSession, ctx: OrgContext) -> AuditRepository:
    return AuditRepository(session, ctx)

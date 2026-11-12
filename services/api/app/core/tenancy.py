"""Tenant isolation.

The `org_id` in a URL is only a *request*. `require_org(permission)` verifies the caller's
membership and permission and yields an `OrgContext`. Org-scoped repositories take an
`OrgContext` and cannot query without it. Non-members get 404 (no existence leak).

Defence in depth (ADR-026): once the org is verified, every transaction of the request runs
with `app.org_id` set, so Postgres row-level security hides other orgs' rows even if a query
forgets its `org_id` filter.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import structlog
from fastapi import Depends
from sqlalchemy import Connection, Select, event, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session, SessionTransaction

from app.core.deps import CurrentUser, SessionDep, get_current_user
from app.core.errors import Forbidden, NotFound
from app.modules.organizations.models import Membership, Organization
from app.modules.rbac.permissions import ROLE_PERMISSIONS, Permission, Role


@dataclass(frozen=True)
class OrgContext:
    org_id: UUID
    user_id: UUID | None  # None for system actors (workers)
    role: Role | None
    permissions: frozenset[Permission]

    def can(self, permission: Permission) -> bool:
        return permission in self.permissions

    @classmethod
    def system(cls, org_id: UUID) -> "OrgContext":
        """Explicit system context for workers; still org-scoped."""
        return cls(org_id=org_id, user_id=None, role=None, permissions=frozenset(Permission))


def org_not_found() -> NotFound:
    return NotFound("Organization not found", code="org.not_found")


async def load_org_context(session: AsyncSession, org_id: UUID, user_id: UUID) -> OrgContext:
    row = (
        await session.execute(
            select(Membership.role)
            .join(Organization, Organization.id == Membership.org_id)
            .where(
                Membership.org_id == org_id,
                Membership.user_id == user_id,
                Organization.deleted_at.is_(None),
            )
        )
    ).first()
    if row is None:
        raise org_not_found()
    role: Role = row[0]
    return OrgContext(org_id=org_id, user_id=user_id, role=role, permissions=ROLE_PERMISSIONS[role])


RLS_ORG_KEY = "rls_org_id"
_SET_ORG = text("SELECT set_config('app.org_id', :org, true)")  # true: transaction-local


@event.listens_for(Session, "after_begin")
def _apply_rls_org(session: Session, _tx: SessionTransaction, connection: Connection) -> None:
    """Re-applies the org at the start of every transaction (services commit mid-request).
    Transaction-local, so it can never leak to the next user of a pooled connection."""
    org = session.info.get(RLS_ORG_KEY)
    if org:
        connection.execute(_SET_ORG, {"org": org})


async def bind_rls_org(session: AsyncSession, org_id: UUID) -> None:
    session.info[RLS_ORG_KEY] = str(org_id)
    if session.in_transaction():  # already begun: apply now; later ones use the listener
        await session.execute(_SET_ORG, {"org": str(org_id)})


def require_org(
    permission: Permission = Permission.ORG_READ,
) -> Callable[..., Awaitable[OrgContext]]:
    async def dependency(
        org_id: UUID,
        session: SessionDep,
        current: CurrentUser = Depends(get_current_user),
    ) -> OrgContext:
        ctx = await load_org_context(session, org_id, current.user.id)
        if not ctx.can(permission):
            raise Forbidden(f"Requires permission '{permission}'")
        await bind_rls_org(session, org_id)
        structlog.contextvars.bind_contextvars(org_id=str(org_id))
        return ctx

    return dependency


class OrgScopedRepository:
    """Base for repositories over tenant-owned tables (models with an `org_id` column)."""

    def __init__(self, session: AsyncSession, ctx: OrgContext) -> None:
        self.session = session
        self.ctx = ctx

    def scoped[*Ts](self, model: Any, stmt: Select[*Ts]) -> Select[*Ts]:
        """Adds `WHERE model.org_id = ctx.org_id`. Every tenant query goes through here."""
        return stmt.where(model.org_id == self.ctx.org_id)

    def select[M](self, model: type[M]) -> Select[M]:
        """`SELECT model ... WHERE org_id = ctx.org_id`."""
        return self.scoped(model, select(model))

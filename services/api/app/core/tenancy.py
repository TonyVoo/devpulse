"""Tenant isolation.

The `org_id` in a URL is only a *request*. `require_org(permission)` verifies the caller's
membership and permission and yields an `OrgContext`. Org-scoped repositories take an
`OrgContext` and cannot query without it. Non-members get 404 (no existence leak).
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import structlog
from fastapi import Depends
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

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

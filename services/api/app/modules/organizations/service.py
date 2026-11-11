"""Organization, membership and invitation use cases."""

import re
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.deps import RequestMeta
from app.core.errors import Conflict, Forbidden, NotFound, Unprocessable
from app.core.security import hash_token, new_opaque_token
from app.core.tenancy import OrgContext, OrgScopedRepository
from app.modules.audit.service import record
from app.modules.organizations.models import Invitation, Membership, Organization
from app.modules.organizations.schemas import MemberOut, OrgWithRoleOut
from app.modules.rbac.permissions import ROLE_RANK, Permission, Role
from app.modules.users.models import User

INVITE_PREFIX = "dp_inv"


def _now() -> datetime:
    return datetime.now(UTC)


def _slugify(name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40] or "org"
    return base if len(base) >= 3 else f"{base}-org"


# ---------------------------------------------------------------- organizations


async def create_org(
    session: AsyncSession, *, user: User, name: str, slug: str | None, meta: RequestMeta
) -> OrgWithRoleOut:
    explicit = slug is not None
    user_id = user.id
    candidate = slug or _slugify(name)
    org: Organization | None = None
    for _ in range(5):
        try:
            # Savepoint: a slug collision rolls back only this insert, not the whole session
            # (a full rollback would expire `user` and everything else loaded so far).
            async with session.begin_nested():
                org = Organization(name=name, slug=candidate)
                session.add(org)
                await session.flush()
            break
        except IntegrityError as e:
            org = None
            if explicit:
                raise Conflict("This slug is already taken", code="org.slug_taken") from e
            candidate = f"{_slugify(name)[:40]}-{secrets.token_hex(2)}"
    if org is None:
        raise Conflict("Could not allocate a unique slug", code="org.slug_taken")
    session.add(Membership(org_id=org.id, user_id=user_id, role=Role.OWNER))
    record(
        session,
        org_id=org.id,
        actor_id=user_id,
        action="org.created",
        target_type="organization",
        target_id=org.id,
        after={"name": org.name, "slug": org.slug},
        meta=meta,
    )
    await session.commit()
    await session.refresh(org)
    return OrgWithRoleOut(
        id=org.id, slug=org.slug, name=org.name, created_at=org.created_at, role=Role.OWNER
    )


async def list_user_orgs(session: AsyncSession, user_id: UUID) -> list[OrgWithRoleOut]:
    rows = await session.execute(
        select(Organization, Membership.role)
        .join(Membership, Membership.org_id == Organization.id)
        .where(Membership.user_id == user_id, Organization.deleted_at.is_(None))
        .order_by(Organization.name)
    )
    return [
        OrgWithRoleOut(id=o.id, slug=o.slug, name=o.name, created_at=o.created_at, role=r)
        for o, r in rows
    ]


class OrgService(OrgScopedRepository):
    """All operations act on `ctx.org_id` only."""

    @property
    def _actor_role(self) -> Role:
        if self.ctx.role is None:  # system contexts have no membership role
            raise Forbidden("A member role is required for this action")
        return self.ctx.role

    async def _org(self) -> Organization:
        org = await self.session.scalar(
            select(Organization).where(
                Organization.id == self.ctx.org_id, Organization.deleted_at.is_(None)
            )
        )
        if org is None:
            raise NotFound("Organization not found", code="org.not_found")
        return org

    async def get(self) -> OrgWithRoleOut:
        org = await self._org()
        return OrgWithRoleOut(
            id=org.id,
            slug=org.slug,
            name=org.name,
            created_at=org.created_at,
            role=self._actor_role,
        )

    async def update(self, *, name: str | None, meta: RequestMeta) -> OrgWithRoleOut:
        org = await self._org()
        if name is not None and name != org.name:
            before = {"name": org.name}
            org.name = name
            record(
                self.session,
                org_id=org.id,
                actor_id=self.ctx.user_id,
                action="org.updated",
                target_type="organization",
                target_id=org.id,
                before=before,
                after={"name": name},
                meta=meta,
            )
            await self.session.commit()
        return await self.get()

    async def soft_delete(self, *, meta: RequestMeta) -> None:
        org = await self._org()
        org.deleted_at = _now()
        record(
            self.session,
            org_id=org.id,
            actor_id=self.ctx.user_id,
            action="org.deleted",
            target_type="organization",
            target_id=org.id,
            meta=meta,
        )
        await self.session.commit()

    # ------------------------------------------------------------ members

    async def list_members(self) -> list[MemberOut]:
        rows = await self.session.execute(
            self.scoped(Membership, select(Membership, User))
            .join(User, User.id == Membership.user_id)
            .order_by(User.display_name)
        )
        return [
            MemberOut(
                user_id=u.id,
                email=u.email,
                display_name=u.display_name,
                avatar_url=u.avatar_url,
                role=m.role,
                joined_at=m.created_at,
            )
            for m, u in rows
        ]

    async def _membership(self, user_id: UUID, *, lock: bool = False) -> Membership:
        stmt = self.select(Membership).where(Membership.user_id == user_id)
        if lock:
            stmt = stmt.with_for_update()
        m = await self.session.scalar(stmt)
        if m is None:
            raise NotFound("Member not found", code="member.not_found")
        return m

    async def _lock_owners(self) -> int:
        """Lock all owner rows of the org, serialising concurrent demotions/removals."""
        owners = await self.session.scalars(
            self.select(Membership).where(Membership.role == Role.OWNER).with_for_update()
        )
        return len(list(owners))

    def _assert_can_assign(self, target_role: Role, current_role: Role) -> None:
        actor = self._actor_role
        # Only owners may grant or take away ownership; others cannot act above their rank.
        if Role.OWNER in (target_role, current_role) and actor != Role.OWNER:
            raise Forbidden("Only owners can change ownership", code="member.owner_required")
        if ROLE_RANK[target_role] > ROLE_RANK[actor] or ROLE_RANK[current_role] > ROLE_RANK[actor]:
            raise Forbidden("Cannot manage a member above your role", code="member.rank")

    async def change_role(self, *, user_id: UUID, role: Role, meta: RequestMeta) -> MemberOut:
        owners = await self._lock_owners()
        m = await self._membership(user_id, lock=True)
        self._assert_can_assign(role, m.role)
        if m.role == Role.OWNER and role != Role.OWNER and owners <= 1:
            raise Conflict("An organization needs at least one owner", code="member.last_owner")
        if m.role != role:
            before = {"role": m.role.value}
            m.role = role
            record(
                self.session,
                org_id=self.ctx.org_id,
                actor_id=self.ctx.user_id,
                action="member.role_changed",
                target_type="user",
                target_id=user_id,
                before=before,
                after={"role": role.value},
                meta=meta,
            )
            await self.session.commit()
        members = {x.user_id: x for x in await self.list_members()}
        return members[user_id]

    async def remove_member(self, *, user_id: UUID, meta: RequestMeta) -> None:
        is_self = user_id == self.ctx.user_id
        if not is_self and not self.ctx.can(Permission.MEMBERS_MANAGE):
            raise Forbidden(f"Requires permission '{Permission.MEMBERS_MANAGE}'")
        owners = await self._lock_owners()
        m = await self._membership(user_id, lock=True)
        if not is_self:
            self._assert_can_assign(m.role, m.role)
        if m.role == Role.OWNER and owners <= 1:
            raise Conflict("An organization needs at least one owner", code="member.last_owner")
        await self.session.delete(m)
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="member.left" if is_self else "member.removed",
            target_type="user",
            target_id=user_id,
            before={"role": m.role.value},
            meta=meta,
        )
        await self.session.commit()

    # ------------------------------------------------------------ invitations

    async def list_invitations(self) -> list[Invitation]:
        return list(
            (
                await self.session.scalars(
                    self.select(Invitation)
                    .where(
                        Invitation.accepted_at.is_(None),
                        Invitation.revoked_at.is_(None),
                        Invitation.expires_at > _now(),
                    )
                    .order_by(Invitation.created_at.desc())
                )
            ).all()
        )

    async def invite(self, *, email: str, role: Role, meta: RequestMeta) -> tuple[Invitation, str]:
        self._assert_can_assign(role, Role.VIEWER)
        already_member = await self.session.scalar(
            self.scoped(Membership, select(func.count()).select_from(Membership))
            .join(User, User.id == Membership.user_id)
            .where(User.email == email)
        )
        if already_member:
            raise Conflict("This person is already a member", code="invitation.already_member")
        # Clear an expired pending invite so the partial unique index doesn't block re-inviting.
        await self.session.execute(
            update(Invitation)
            .where(
                Invitation.org_id == self.ctx.org_id,
                Invitation.email == email,
                Invitation.accepted_at.is_(None),
                Invitation.revoked_at.is_(None),
                Invitation.expires_at <= _now(),
            )
            .values(revoked_at=_now())
        )
        raw = new_opaque_token(INVITE_PREFIX)
        inv = Invitation(
            org_id=self.ctx.org_id,
            email=email,
            role=role,
            token_hash=hash_token(raw),
            invited_by=self.ctx.user_id,
            expires_at=_now() + timedelta(seconds=get_settings().invitation_ttl_s),
        )
        self.session.add(inv)
        try:
            await self.session.flush()
        except IntegrityError as e:
            await self.session.rollback()
            raise Conflict(
                "A pending invitation already exists for this email", code="invitation.pending"
            ) from e
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="invitation.created",
            target_type="invitation",
            target_id=inv.id,
            after={"email": email, "role": role.value},
            meta=meta,
        )
        await self.session.commit()
        await self.session.refresh(inv)
        return inv, raw

    async def revoke_invitation(self, *, invitation_id: UUID, meta: RequestMeta) -> None:
        inv = await self.session.scalar(
            self.select(Invitation).where(
                Invitation.id == invitation_id,
                Invitation.accepted_at.is_(None),
                Invitation.revoked_at.is_(None),
            )
        )
        if inv is None:
            raise NotFound("Invitation not found", code="invitation.not_found")
        inv.revoked_at = _now()
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="invitation.revoked",
            target_type="invitation",
            target_id=inv.id,
            meta=meta,
        )
        await self.session.commit()


async def accept_invitation(
    session: AsyncSession, *, user: User, raw_token: str, meta: RequestMeta
) -> OrgWithRoleOut:
    inv = await session.scalar(
        select(Invitation).where(Invitation.token_hash == hash_token(raw_token)).with_for_update()
    )
    # One error for every failure mode: don't reveal whether a token exists or for whom.
    invalid = NotFound("Invitation is invalid or has expired", code="invitation.invalid")
    if inv is None or inv.accepted_at or inv.revoked_at or inv.expires_at <= _now():
        raise invalid
    if inv.email != user.email:
        raise invalid
    org = await session.scalar(
        select(Organization).where(Organization.id == inv.org_id, Organization.deleted_at.is_(None))
    )
    if org is None:
        raise invalid
    existing = await session.scalar(
        select(Membership).where(Membership.org_id == inv.org_id, Membership.user_id == user.id)
    )
    if existing is not None:
        raise Unprocessable("You are already a member", code="invitation.already_member")
    inv.accepted_at = _now()
    session.add(
        Membership(org_id=inv.org_id, user_id=user.id, role=inv.role, invited_by=inv.invited_by)
    )
    record(
        session,
        org_id=inv.org_id,
        actor_id=user.id,
        action="member.joined",
        target_type="user",
        target_id=user.id,
        after={"role": inv.role.value},
        meta=meta,
    )
    await session.commit()
    return OrgWithRoleOut(
        id=org.id, slug=org.slug, name=org.name, created_at=org.created_at, role=inv.role
    )


def org_service(session: AsyncSession, ctx: OrgContext) -> OrgService:
    return OrgService(session, ctx)

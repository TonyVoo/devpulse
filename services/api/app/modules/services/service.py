"""Service catalog and ingest keys."""

import re
import secrets
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError

from app.core.deps import RequestMeta
from app.core.errors import Conflict, NotFound, Unprocessable
from app.core.pagination import MAX_LIMIT, Page, decode_text_cursor, encode_text_cursor
from app.core.security import hash_token
from app.core.tenancy import OrgScopedRepository
from app.modules.audit.service import record
from app.modules.services.models import Health, IngestKey, Service
from app.modules.services.schemas import (
    IngestKeyCreateIn,
    ServiceCreateIn,
    ServiceOut,
    ServiceUpdateIn,
)

INGEST_PREFIX = "dp_ingest"


def _now() -> datetime:
    return datetime.now(UTC)


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:64]
    return slug if len(slug) >= 2 else f"{slug or 'svc'}-svc"


def check_version(current: int, if_match: str | None) -> None:
    """Optimistic concurrency: `If-Match: "<version>"` must equal the current version."""
    if if_match is None:
        return
    try:
        expected = int(if_match.strip().strip("W/").strip('"'))
    except ValueError as e:
        raise Unprocessable(
            "If-Match must be a version number", code="conflict.bad_if_match"
        ) from e
    if expected != current:
        raise Conflict(
            "This resource was changed by someone else. Reload and try again.",
            code="conflict.version_mismatch",
            extra={"current_version": current},
        )


class ServiceCatalog(OrgScopedRepository):
    async def get(self, service_id: UUID) -> Service:
        svc = await self.session.scalar(
            self.select(Service).where(Service.id == service_id, Service.deleted_at.is_(None))
        )
        if svc is None:
            raise NotFound("Service not found", code="service.not_found")
        return svc

    async def page(
        self,
        *,
        limit: int,
        cursor: str | None,
        health: list[Health] | None,
        environment: str | None,
        q: str | None,
    ) -> Page[ServiceOut]:
        """Ordered by name, then id (keyset). Health counts come from the overview endpoint."""
        limit = max(1, min(limit, MAX_LIMIT))
        stmt = self.select(Service).where(Service.deleted_at.is_(None))
        if health:
            stmt = stmt.where(Service.health.in_(health))
        if environment:
            stmt = stmt.where(Service.environment == environment)
        if q:
            like = f"%{q.strip()[:80]}%"
            stmt = stmt.where(or_(Service.name.ilike(like), Service.slug.ilike(like)))
        if cursor:
            name, last_id = decode_text_cursor(cursor)
            stmt = stmt.where(
                or_(Service.name > name, and_(Service.name == name, Service.id > last_id))
            )
        rows = list(
            (
                await self.session.scalars(stmt.order_by(Service.name, Service.id).limit(limit + 1))
            ).all()
        )
        nxt = (
            encode_text_cursor(rows[limit - 1].name, rows[limit - 1].id)
            if len(rows) > limit
            else None
        )
        return Page(items=[ServiceOut.model_validate(r) for r in rows[:limit]], next_cursor=nxt)

    async def create(self, body: ServiceCreateIn, meta: RequestMeta) -> Service:
        svc = Service(
            org_id=self.ctx.org_id,
            slug=body.slug or slugify(body.name),
            name=body.name,
            environment=body.environment,
            tier=body.tier,
            description=body.description,
            owner_team=body.owner_team,
            repo_url=str(body.repo_url).rstrip("/") if body.repo_url else None,
            tags=body.tags,
        )
        self.session.add(svc)
        try:
            await self.session.flush()
        except IntegrityError as e:
            await self.session.rollback()
            raise Conflict(
                f"A service '{svc.slug}' already exists in {svc.environment}",
                code="service.slug_taken",
            ) from e
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="service.created",
            target_type="service",
            target_id=svc.id,
            after={"slug": svc.slug, "environment": svc.environment},
            meta=meta,
        )
        await self.session.commit()
        await self.session.refresh(svc)
        return svc

    async def update(
        self, service_id: UUID, body: ServiceUpdateIn, if_match: str | None, meta: RequestMeta
    ) -> Service:
        svc = await self.get(service_id)
        check_version(svc.version, if_match)
        changes: dict[str, Any] = {}
        for field, value in body.model_dump(exclude_unset=True).items():
            if field == "repo_url" and value is not None:
                value = str(value).rstrip("/")
            if getattr(svc, field) != value:
                changes[field] = value
                setattr(svc, field, value)
        if changes:
            svc.version += 1
            record(
                self.session,
                org_id=self.ctx.org_id,
                actor_id=self.ctx.user_id,
                action="service.updated",
                target_type="service",
                target_id=svc.id,
                after={k: str(v) for k, v in changes.items()},
                meta=meta,
            )
            await self.session.commit()
            await self.session.refresh(svc)
        return svc

    async def delete(self, service_id: UUID, meta: RequestMeta) -> None:
        svc = await self.get(service_id)
        svc.deleted_at = _now()
        svc.version += 1
        # Free the slug for reuse; history keeps the id.
        svc.slug = f"{svc.slug[:40]}-deleted-{secrets.token_hex(3)}"
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="service.deleted",
            target_type="service",
            target_id=svc.id,
            meta=meta,
        )
        await self.session.commit()

    # ---------------------------------------------------------------- ingest keys

    async def list_keys(self) -> list[IngestKey]:
        return list(
            (
                await self.session.scalars(
                    self.select(IngestKey).order_by(IngestKey.created_at.desc())
                )
            ).all()
        )

    async def create_key(
        self, body: IngestKeyCreateIn, meta: RequestMeta, *, is_demo: bool = False
    ) -> tuple[IngestKey, str]:
        if body.service_id is not None:
            await self.get(body.service_id)  # must belong to this org
        raw = f"{INGEST_PREFIX}_{secrets.token_urlsafe(32)}"
        key = IngestKey(
            org_id=self.ctx.org_id,
            service_id=body.service_id,
            name=body.name,
            prefix=raw[: len(INGEST_PREFIX) + 7],
            key_hash=hash_token(raw),
            scopes=sorted(set(body.scopes)),
            is_demo=is_demo,
            created_by=self.ctx.user_id,
        )
        self.session.add(key)
        await self.session.flush()
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="ingest_key.created",
            target_type="ingest_key",
            target_id=key.id,
            after={"name": key.name, "scopes": key.scopes},
            meta=meta,
        )
        await self.session.commit()
        await self.session.refresh(key)
        return key, raw

    async def revoke_key(self, key_id: UUID, meta: RequestMeta) -> None:
        key = await self.session.scalar(
            self.select(IngestKey).where(IngestKey.id == key_id, IngestKey.revoked_at.is_(None))
        )
        if key is None:
            raise NotFound("Ingest key not found", code="ingest_key.not_found")
        key.revoked_at = _now()
        record(
            self.session,
            org_id=self.ctx.org_id,
            actor_id=self.ctx.user_id,
            action="ingest_key.revoked",
            target_type="ingest_key",
            target_id=key.id,
            meta=meta,
        )
        await self.session.commit()


async def find_by_slug(session: Any, org_id: UUID, slug: str, environment: str) -> Service | None:
    result: Service | None = await session.scalar(
        select(Service).where(
            Service.org_id == org_id,
            Service.slug == slug,
            Service.environment == environment,
            Service.deleted_at.is_(None),
        )
    )
    return result

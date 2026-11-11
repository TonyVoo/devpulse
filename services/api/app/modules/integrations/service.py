"""Integrations (GitHub) and signed webhooks."""

import hashlib
import hmac
import json
import secrets
from datetime import UTC, datetime
from typing import Annotated, Any, Literal
from uuid import UUID

import structlog
from cryptography.fernet import Fernet, InvalidToken
from fastapi import APIRouter, Depends, Header, Request, status
from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.config import get_settings
from app.core.deps import RequestMetaDep, SessionDep
from app.core.errors import AppError, NotFound, Unauthorized, Unprocessable
from app.core.tenancy import OrgContext, OrgScopedRepository, require_org
from app.modules.audit.service import record
from app.modules.deployments.models import DeploySource, DeployStatus
from app.modules.deployments.service import upsert_deployment
from app.modules.integrations.models import Integration, IntegrationKind, WebhookDelivery
from app.modules.rbac.permissions import Permission
from app.modules.services.models import Service

log = structlog.get_logger(__name__)
MAX_WEBHOOK_BYTES = 1_000_000


class IntegrationsDisabled(AppError):
    status, code, title = 503, "integrations.disabled", "Integrations are not configured"


def _fernet() -> Fernet:
    key = get_settings().encryption_key
    if key is None:
        raise IntegrationsDisabled("Set ENCRYPTION_KEY on the server to enable integrations")
    return Fernet(key.get_secret_value().encode())


def encrypt(secret: str) -> str:
    return _fernet().encrypt(secret.encode()).decode()


def decrypt(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken as e:
        raise IntegrationsDisabled("Integration secret can't be decrypted (key rotated?)") from e


def verify_github_signature(secret: str, body: bytes, header: str | None) -> bool:
    if not header or not header.startswith("sha256="):
        return False
    expected = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header)


class IntegrationIn(BaseModel):
    kind: Literal["github"] = "github"
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
    # owner/repo → service id. Repos not listed fall back to matching services.repo_url.
    repo_map: dict[str, UUID] = Field(default_factory=dict, max_length=200)


class IntegrationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    kind: IntegrationKind
    name: str
    config: dict[str, Any]
    enabled: bool
    created_at: datetime
    webhook_path: str = ""


class IntegrationCreatedOut(IntegrationOut):
    webhook_secret: str = Field(description="Shown once. Paste into GitHub's webhook settings.")


def _out(i: Integration) -> IntegrationOut:
    return IntegrationOut.model_validate(i).model_copy(
        update={"webhook_path": f"/webhooks/github/{i.id}"}
    )


router = APIRouter(tags=["integrations"])
Manage = Annotated[OrgContext, Depends(require_org(Permission.INTEGRATIONS_MANAGE))]


@router.get("/api/v1/orgs/{org_id}/integrations", response_model=list[IntegrationOut])
async def list_integrations(ctx: Manage, session: SessionDep) -> list[IntegrationOut]:
    repo = OrgScopedRepository(session, ctx)
    rows = await session.scalars(repo.select(Integration).order_by(Integration.created_at))
    return [_out(i) for i in rows.all()]


@router.post(
    "/api/v1/orgs/{org_id}/integrations",
    response_model=IntegrationCreatedOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_integration(
    body: IntegrationIn, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> IntegrationCreatedOut:
    if body.repo_map:
        owned = set(
            (
                await session.scalars(
                    select(Service.id).where(
                        Service.org_id == ctx.org_id, Service.id.in_(body.repo_map.values())
                    )
                )
            ).all()
        )
        if owned != set(body.repo_map.values()):
            raise Unprocessable("repo_map references unknown services", code="service.not_found")
    secret = secrets.token_urlsafe(32)
    integ = Integration(
        org_id=ctx.org_id,
        kind=IntegrationKind.GITHUB,
        name=body.name,
        config={"repo_map": {k.lower(): str(v) for k, v in body.repo_map.items()}},
        secret_encrypted=encrypt(secret),
        created_by=ctx.user_id,
    )
    session.add(integ)
    await session.flush()
    record(
        session,
        org_id=ctx.org_id,
        actor_id=ctx.user_id,
        action="integration.created",
        target_type="integration",
        target_id=integ.id,
        after={"kind": "github", "name": body.name},
        meta=meta,
    )
    await session.commit()
    await session.refresh(integ)
    return IntegrationCreatedOut(**_out(integ).model_dump(), webhook_secret=secret)


@router.delete(
    "/api/v1/orgs/{org_id}/integrations/{integration_id}", status_code=status.HTTP_204_NO_CONTENT
)
async def delete_integration(
    integration_id: UUID, ctx: Manage, session: SessionDep, meta: RequestMetaDep
) -> None:
    repo = OrgScopedRepository(session, ctx)
    integ = await session.scalar(repo.select(Integration).where(Integration.id == integration_id))
    if integ is None:
        raise NotFound("Integration not found", code="integration.not_found")
    await session.delete(integ)
    record(
        session,
        org_id=ctx.org_id,
        actor_id=ctx.user_id,
        action="integration.deleted",
        target_type="integration",
        target_id=integration_id,
        meta=meta,
    )
    await session.commit()


_GH_STATE = {
    "success": DeployStatus.SUCCEEDED,
    "failure": DeployStatus.FAILED,
    "error": DeployStatus.FAILED,
    "inactive": DeployStatus.ROLLED_BACK,
    "pending": DeployStatus.STARTED,
    "queued": DeployStatus.STARTED,
    "in_progress": DeployStatus.STARTED,
}


@router.post("/webhooks/github/{integration_id}", status_code=status.HTTP_202_ACCEPTED)
async def github_webhook(
    integration_id: UUID,
    request: Request,
    session: SessionDep,
    x_github_event: Annotated[str, Header()],
    x_github_delivery: Annotated[str, Header(max_length=80)],
    x_hub_signature_256: Annotated[str | None, Header()] = None,
) -> dict[str, str]:
    """Signature is verified before anything is parsed. Deliveries are deduplicated."""
    body = await request.body()
    if len(body) > MAX_WEBHOOK_BYTES:
        raise Unprocessable("Payload too large", code="webhook.too_large")
    integ = await session.get(Integration, integration_id)
    # Same error for unknown integration and bad signature (don't confirm ids exist).
    if (
        integ is None
        or not integ.enabled
        or not verify_github_signature(decrypt(integ.secret_encrypted), body, x_hub_signature_256)
    ):
        raise Unauthorized("Invalid webhook signature", code="webhook.invalid_signature")

    delivery = WebhookDelivery(
        org_id=integ.org_id,
        integration_id=integ.id,
        delivery_id=x_github_delivery,
        event=x_github_event,
        outcome="received",
    )
    session.add(delivery)
    try:
        await session.flush()
    except IntegrityError:
        await session.rollback()
        return {"status": "duplicate"}

    try:
        payload = json.loads(body)
        delivery.outcome = await _handle_github(session, integ, x_github_event, payload)
    except (ValueError, KeyError, TypeError) as e:
        delivery.outcome, delivery.error = "error", f"{type(e).__name__}: {e}"[:500]
        log.warning(
            "github_webhook_unprocessable", integration_id=str(integ.id), error=delivery.error
        )
    await session.commit()
    return {"status": delivery.outcome}


async def _service_for_repo(
    session: Any, integ: Integration, full_name: str, html_url: str
) -> Service | None:
    mapped = integ.config.get("repo_map", {}).get(full_name.lower())
    if mapped:
        svc: Service | None = await session.scalar(
            select(Service).where(
                Service.org_id == integ.org_id,
                Service.id == UUID(mapped),
                Service.deleted_at.is_(None),
            )
        )
        return svc
    svc = await session.scalar(
        select(Service)
        .where(
            Service.org_id == integ.org_id,
            Service.repo_url.ilike(html_url.rstrip("/")),
            Service.deleted_at.is_(None),
        )
        .limit(1)
    )
    return svc


async def _handle_github(session: Any, integ: Integration, event: str, p: dict[str, Any]) -> str:
    if event == "ping":
        return "pong"
    if event not in ("deployment", "deployment_status"):
        return "ignored"
    repo = p["repository"]
    svc = await _service_for_repo(session, integ, repo["full_name"], repo["html_url"])
    if svc is None:
        return "unmapped_repository"
    d = p["deployment"]
    commit = (p.get("deployment") or {}).get("sha")
    values: dict[str, object] = {
        "environment": str(d.get("environment") or svc.environment)[:32].lower(),
        "version": str(d.get("ref") or commit or d["id"])[:80],
        "commit_sha": commit,
        "commit_message": (d.get("description") or None),
        "commit_author": (d.get("creator") or {}).get("login"),
        "branch": d.get("ref"),
        "repo_url": repo["html_url"],
        "started_at": datetime.fromisoformat(d["created_at"].replace("Z", "+00:00")),
    }
    if event == "deployment":
        values["status"] = DeployStatus.STARTED
    else:
        state = p["deployment_status"]["state"]
        values["status"] = _GH_STATE.get(state, DeployStatus.STARTED)
        if values["status"] != DeployStatus.STARTED:
            values["finished_at"] = datetime.now(UTC)
    await upsert_deployment(
        session,
        org_id=integ.org_id,
        service_id=svc.id,
        source=DeploySource.GITHUB,
        external_id=str(d["id"]),
        values=values,
        # A late/replayed `deployment` event must not move a finished deploy back to started.
        insert_only=frozenset({"status"}) if event == "deployment" else frozenset(),
    )
    return "processed"

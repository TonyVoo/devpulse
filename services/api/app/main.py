from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import structlog
from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.core.config import get_settings
from app.core.db import get_engine
from app.core.errors import install_error_handlers
from app.core.health import router as health_router
from app.core.logging import RequestContextMiddleware, configure_logging
from app.core.observability import init_sentry
from app.core.redis import get_redis
from app.core.security_middleware import SecurityMiddleware
from app.modules.ai.router import router as ai_router
from app.modules.alerts.router import router as alerts_router
from app.modules.audit.router import router as audit_router
from app.modules.auth.router import router as auth_router
from app.modules.deployments.service import ingest_router as deploy_ingest_router
from app.modules.deployments.service import router as deployments_router
from app.modules.incidents.router import router as incidents_router
from app.modules.integrations.service import router as integrations_router
from app.modules.notifications.router import router as notifications_router
from app.modules.organizations.router import router as org_router
from app.modules.overview.router import router as overview_router
from app.modules.realtime.gateway import router as realtime_router
from app.modules.services.router import router as services_router
from app.modules.sync.router import router as sync_router
from app.modules.telemetry.ingest import router as ingest_router
from app.modules.telemetry.metrics import router as metrics_router
from app.modules.users.router import router as me_router

API_PREFIX = "/api/v1"


async def _warn_if_rls_bypassed() -> None:
    """Row-level security never applies to superusers or BYPASSRLS roles (ADR-026)."""
    try:
        async with get_engine().connect() as conn:
            bypass = await conn.scalar(
                text("SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname = current_user")
            )
    except Exception:  # the database may not be up yet; readiness reports that
        return
    if bypass:
        structlog.get_logger(__name__).warning(
            "rls_not_enforced",
            detail="The database role is a superuser or has BYPASSRLS; tenant row-level "
            "security is not enforced. Use an ordinary role in staging/production.",
        )


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    await _warn_if_rls_bypassed()
    yield
    await get_engine().dispose()
    await get_redis().aclose()


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level, json=settings.log_json)
    init_sentry("api")

    app = FastAPI(
        title="DevPulse API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
    )
    install_error_handlers(app)
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(
        SecurityMiddleware,
        max_body_bytes=settings.max_body_bytes,
        max_ingest_body_bytes=settings.max_ingest_body_bytes,
        hsts=settings.is_deployed,
    )
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "If-Match"],
        )

    v1 = APIRouter(prefix=API_PREFIX)
    for r in (
        auth_router,
        me_router,
        org_router,
        audit_router,
        services_router,
        metrics_router,
        incidents_router,
        alerts_router,
        overview_router,
        deployments_router,
        sync_router,
        notifications_router,
        ai_router,
    ):
        v1.include_router(r)
    app.include_router(v1)
    # Routers that span prefixes: /api/v1/orgs/… plus machine endpoints (/ingest, /webhooks).
    app.include_router(ingest_router)
    app.include_router(deploy_ingest_router)
    app.include_router(integrations_router)
    app.include_router(realtime_router)
    app.include_router(health_router)
    return app


app = create_app()

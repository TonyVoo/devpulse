from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import sentry_sdk
from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.db import get_engine
from app.core.errors import install_error_handlers
from app.core.health import router as health_router
from app.core.logging import RequestContextMiddleware, configure_logging
from app.core.redis import get_redis
from app.modules.audit.router import router as audit_router
from app.modules.auth.router import router as auth_router
from app.modules.organizations.router import router as org_router
from app.modules.users.router import router as me_router

API_PREFIX = "/api/v1"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield
    await get_engine().dispose()
    await get_redis().aclose()


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level, json=settings.log_json)
    if settings.sentry_dsn:
        sentry_sdk.init(
            dsn=settings.sentry_dsn, environment=settings.app_env, send_default_pii=False
        )

    app = FastAPI(
        title="DevPulse API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
    )
    install_error_handlers(app)
    app.add_middleware(RequestContextMiddleware)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "If-Match"],
        )

    v1 = APIRouter(prefix=API_PREFIX)
    for r in (auth_router, me_router, org_router, audit_router):
        v1.include_router(r)
    app.include_router(v1)
    app.include_router(health_router)
    return app


app = create_app()

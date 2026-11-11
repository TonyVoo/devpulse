"""Liveness/readiness. Readiness checks DB, Redis and that migrations are at head."""

from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.core.db import get_engine
from app.core.redis import get_redis

router = APIRouter(tags=["health"])

_ALEMBIC_INI = Path(__file__).resolve().parents[2] / "alembic.ini"


def _head_revisions() -> set[str]:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_INI.parent / "migrations"))
    return set(ScriptDirectory.from_config(cfg).get_heads())


@router.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/readyz")
async def readyz() -> JSONResponse:
    checks: dict[str, str] = {}
    try:
        async with get_engine().connect() as conn:
            await conn.execute(text("SELECT 1"))
            current = set(
                (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalars()
            )
        checks["database"] = "ok"
        checks["migrations"] = "ok" if current == _head_revisions() else "pending"
    except Exception:
        checks.setdefault("database", "error")
        checks.setdefault("migrations", "unknown")
    try:
        await get_redis().ping()
        checks["redis"] = "ok"
    except Exception:
        checks["redis"] = "error"
    ready = all(v == "ok" for v in checks.values())
    return JSONResponse(
        {"status": "ready" if ready else "not_ready", "checks": checks},
        status_code=200 if ready else 503,
    )

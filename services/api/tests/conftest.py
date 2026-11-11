"""Test harness: real PostgreSQL + Redis (from Docker Compose or CI service containers).

A dedicated `<db>_test` database is created and migrated once per session via Alembic,
so tests also exercise the migrations. Tables are truncated between tests.
"""

import asyncio
import os
import sys
from collections.abc import AsyncIterator
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import asyncpg
import pytest

API_DIR = Path(__file__).resolve().parents[1]


def _load_env_file(path: Path) -> None:
    """Minimal .env reader for host runs; real env vars (CI) take precedence."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())


_load_env_file(API_DIR / ".env")

_base_url = os.environ.get(
    "DATABASE_URL", "postgresql+asyncpg://devpulse:devpulse@localhost:55432/devpulse"
)
_parts = urlsplit(_base_url)
TEST_DB = _parts.path.lstrip("/") + "_test"
TEST_DATABASE_URL = urlunsplit(_parts._replace(path="/" + TEST_DB))

_redis_parts = urlsplit(os.environ.get("REDIS_URL", "redis://localhost:56379/0"))
TEST_REDIS_URL = urlunsplit(_redis_parts._replace(path="/15"))

os.environ.update(
    APP_ENV="test",
    DATABASE_URL=TEST_DATABASE_URL,
    REDIS_URL=TEST_REDIS_URL,
    JWT_SIGNING_KEY="test-signing-key-0123456789abcdefghijklmnopqrstuvwxyz",
    LOG_JSON="false",
    LOG_LEVEL="WARNING",
    LOGIN_RATE_LIMIT="5",
    REFRESH_REUSE_GRACE_S="0",  # strict by default; grace covered by a dedicated test
)

import httpx  # noqa: E402

from app.core.redis import get_redis  # noqa: E402
from app.main import create_app  # noqa: E402


def _raw_dsn(url: str) -> str:
    return url.replace("postgresql+asyncpg://", "postgresql://", 1)


@pytest.fixture(scope="session", autouse=True)
async def _database() -> AsyncIterator[None]:
    admin = await asyncpg.connect(_raw_dsn(urlunsplit(_parts._replace(path="/postgres"))))
    try:
        await admin.execute(f'DROP DATABASE IF EXISTS "{TEST_DB}" WITH (FORCE)')
        await admin.execute(f'CREATE DATABASE "{TEST_DB}"')
    finally:
        await admin.close()
    proc = await asyncio.create_subprocess_exec(
        sys.executable,
        "-m",
        "alembic",
        "upgrade",
        "head",
        cwd=API_DIR,
        env={**os.environ},
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    assert proc.returncode == 0, out.decode()
    yield


TABLES = "audit_logs, invitations, memberships, refresh_tokens, devices, organizations, users"


@pytest.fixture(autouse=True)
async def _clean() -> AsyncIterator[None]:
    conn = await asyncpg.connect(_raw_dsn(TEST_DATABASE_URL))
    try:
        await conn.execute(f"TRUNCATE {TABLES} RESTART IDENTITY CASCADE")
    finally:
        await conn.close()
    await get_redis().flushdb()
    yield


@pytest.fixture(scope="session")
def app():  # type: ignore[no-untyped-def]
    return create_app()


@pytest.fixture
async def client(app) -> AsyncIterator[httpx.AsyncClient]:  # type: ignore[no-untyped-def]
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test/api/v1") as c:
        yield c


@pytest.fixture
def db_dsn() -> str:
    return _raw_dsn(TEST_DATABASE_URL)

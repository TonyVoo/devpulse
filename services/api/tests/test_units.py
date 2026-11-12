"""Pure unit tests (no I/O beyond what fixtures set up)."""

import itertools
from datetime import UTC, datetime
from uuid import UUID

import asyncpg
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import Unprocessable
from app.core.ids import uuid7
from app.core.pagination import decode_cursor, encode_cursor
from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)
from app.modules.rbac.permissions import ROLE_PERMISSIONS, Permission, Role, has_permission
from app.workers.tasks import purge_expired_refresh_tokens_async


def test_uuid7_version_variant_and_order() -> None:
    ids = [uuid7() for _ in range(200)]
    assert all(u.version == 7 and u.variant == "specified in RFC 4122" for u in ids)
    timestamps = [u.int >> 80 for u in ids]
    assert timestamps == sorted(timestamps)


def test_cursor_round_trip_and_rejects_garbage() -> None:
    ts, id_ = datetime(2026, 11, 11, 10, 0, tzinfo=UTC), uuid7()
    assert decode_cursor(encode_cursor(ts, id_)) == (ts, id_)
    with pytest.raises(Unprocessable):
        decode_cursor("not-a-cursor")


def test_password_hashing() -> None:
    h = hash_password("a-long-enough-password")
    assert h.startswith("$argon2id$")
    assert verify_password("a-long-enough-password", h)
    assert not verify_password("wrong", h)
    assert not verify_password("anything", None)


def test_access_token_round_trip() -> None:
    uid, sid = uuid7(), uuid7()
    token, ttl = create_access_token(uid, sid)
    claims = decode_access_token(token)
    assert (claims.user_id, claims.session_id) == (uid, sid)
    assert ttl > 0


def test_role_permissions_are_monotonic() -> None:
    order = [Role.VIEWER, Role.ENGINEER, Role.ADMIN, Role.OWNER]
    for lower, higher in itertools.pairwise(order):
        assert ROLE_PERMISSIONS[lower] <= ROLE_PERMISSIONS[higher]
    assert has_permission(Role.OWNER, Permission.ORG_DELETE)
    assert not has_permission(Role.ADMIN, Permission.ORG_DELETE)
    assert not has_permission(Role.VIEWER, Permission.INCIDENTS_ACT)


def _settings(**overrides: object) -> Settings:
    base: dict[str, object] = {
        "database_url": "postgresql+asyncpg://u:p@h/db",
        "redis_url": "redis://h:6379/0",
        "jwt_signing_key": "x" * 40,
    }
    return Settings(_env_file=None, **{**base, **overrides})  # type: ignore[arg-type]


def test_settings_validation() -> None:
    assert _settings().app_env == "test"  # from env set in conftest
    # Plain PostgreSQL URLs are switched to the async driver; other databases are rejected.
    assert _settings(database_url="postgresql://u:p@h/db").database_url.startswith(
        "postgresql+asyncpg://"
    )
    with pytest.raises(ValidationError):
        _settings(database_url="sqlite:///db.sqlite3")
    with pytest.raises(ValidationError):
        _settings(jwt_signing_key="short")
    with pytest.raises(ValidationError):
        _settings(app_env="production", jwt_signing_key="change-me-" + "x" * 40)


async def test_purge_expired_refresh_tokens(client, db_dsn: str) -> None:  # type: ignore[no-untyped-def]
    from tests.helpers import register

    acct = await register(client, "purge@example.com")
    conn = await asyncpg.connect(db_dsn)
    try:
        await conn.execute("UPDATE refresh_tokens SET expires_at = now() - interval '30 days'")
    finally:
        await conn.close()
    from tests.conftest import TEST_DATABASE_URL

    deleted = await purge_expired_refresh_tokens_async(TEST_DATABASE_URL)
    assert deleted == 1
    assert UUID(acct.id)


async def test_audit_log_is_append_only(client, db_dsn: str) -> None:  # type: ignore[no-untyped-def]
    from tests.helpers import create_org, register

    owner = await register(client, "audit@example.com")
    await create_org(client, owner)
    conn = await asyncpg.connect(db_dsn)
    try:
        with pytest.raises(asyncpg.RaiseError, match="append-only"):
            await conn.execute("UPDATE audit_logs SET action = 'tampered'")
    finally:
        await conn.close()


def test_managed_postgres_urls_are_normalised() -> None:
    from app.core.config import Settings

    v = Settings._async_driver("postgres://u:p@h:5432/db?sslmode=require")
    assert v == "postgresql+asyncpg://u:p@h:5432/db?ssl=require"
    assert Settings._async_driver("postgresql://u@h/db") == "postgresql+asyncpg://u@h/db"
    import pytest

    with pytest.raises(ValueError):
        Settings._async_driver("mysql://u@h/db")


def test_platform_generated_secrets_become_fernet_keys() -> None:
    import pytest
    from cryptography.fernet import Fernet

    from app.modules.integrations.service import fernet_key

    real = Fernet.generate_key().decode()
    assert fernet_key(real) == real.encode()  # existing keys keep working
    derived = fernet_key("Z2VuZXJhdGVkK2J5L3JlbmRlcj09LWJhc2U2NC1zZWNyZXQ=")  # has + and /
    token = Fernet(derived).encrypt(b"webhook-secret")
    assert Fernet(derived).decrypt(token) == b"webhook-secret"
    with pytest.raises(ValueError):
        fernet_key("short")


async def test_healthz_reports_the_release(client) -> None:  # type: ignore[no-untyped-def]
    r = await client.get("http://test/healthz")
    assert r.json()["status"] == "ok" and r.json()["release"]

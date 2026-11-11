import asyncio

import httpx
import pytest

from tests.helpers import PASSWORD, problem, register


async def test_register_returns_tokens_and_profile(client: httpx.AsyncClient) -> None:
    acct = await register(client, "  Ada@Example.COM ", "Ada")
    r = await client.get("/me", headers=acct.h)
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == "ada@example.com"  # normalised
    assert body["memberships"] == []
    assert "password_hash" not in body


async def test_register_duplicate_email_conflicts(client: httpx.AsyncClient) -> None:
    await register(client, "dup@example.com")
    r = await client.post(
        "/auth/register",
        json={"email": "DUP@example.com", "password": PASSWORD, "display_name": "x"},
    )
    assert r.status_code == 409
    assert problem(r)["code"] == "auth.email_taken"


async def test_register_rejects_short_password(client: httpx.AsyncClient) -> None:
    r = await client.post(
        "/auth/register", json={"email": "a@example.com", "password": "short", "display_name": "a"}
    )
    assert r.status_code == 422
    body = problem(r)
    assert body["code"] == "validation.failed"
    assert any(e["loc"][-1] == "password" for e in body["errors"])


async def test_login_success_and_wrong_password(client: httpx.AsyncClient) -> None:
    await register(client, "bob@example.com")
    ok = await client.post("/auth/login", json={"email": "bob@example.com", "password": PASSWORD})
    assert ok.status_code == 200
    assert ok.json()["token_type"] == "bearer"

    bad = await client.post("/auth/login", json={"email": "bob@example.com", "password": "nope"})
    assert bad.status_code == 401
    assert problem(bad)["code"] == "auth.invalid_credentials"

    unknown = await client.post(
        "/auth/login", json={"email": "ghost@example.com", "password": PASSWORD}
    )
    assert unknown.status_code == 401
    assert problem(unknown)["code"] == "auth.invalid_credentials"  # no user enumeration


async def test_login_is_rate_limited(client: httpx.AsyncClient) -> None:
    await register(client, "rl@example.com")
    codes = []
    for _ in range(7):  # LOGIN_RATE_LIMIT=5 in tests
        r = await client.post("/auth/login", json={"email": "rl@example.com", "password": "x"})
        codes.append(r.status_code)
    assert codes[:5] == [401] * 5
    assert codes[5] == 429
    assert "retry-after" in {k.lower() for k in r.headers}


async def test_missing_and_garbage_tokens(client: httpx.AsyncClient) -> None:
    r = await client.get("/me")
    assert r.status_code == 401
    assert problem(r)["code"] == "auth.unauthorized"
    r = await client.get("/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401
    assert problem(r)["code"] == "auth.invalid_token"


async def test_refresh_rotates_tokens(client: httpx.AsyncClient) -> None:
    acct = await register(client, "rot@example.com")
    r = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert r.status_code == 200
    new = r.json()
    assert new["refresh_token"] != acct.refresh
    assert new["session_id"] == acct.session_id  # same session family
    me = await client.get("/me", headers={"Authorization": f"Bearer {new['access_token']}"})
    assert me.status_code == 200


async def test_refresh_reuse_revokes_whole_family(client: httpx.AsyncClient) -> None:
    acct = await register(client, "theft@example.com")
    first = (await client.post("/auth/refresh", json={"refresh_token": acct.refresh})).json()

    # Attacker replays the original (already rotated) token.
    replay = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert replay.status_code == 401
    assert problem(replay)["code"] == "auth.refresh_reused"

    # The legitimate client's newer token is now dead too.
    r = await client.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert r.status_code == 401


async def test_refresh_reuse_within_grace_window_is_tolerated(
    client: httpx.AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "refresh_reuse_grace_s", 10)
    acct = await register(client, "tabs@example.com")
    first = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    second = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert first.status_code == second.status_code == 200
    assert first.json()["session_id"] == second.json()["session_id"]
    assert len((await client.get("/me/sessions", headers=acct.h)).json()) == 1

    # After logout the grace window no longer applies.
    me = {"Authorization": f"Bearer {second.json()['access_token']}"}
    assert (await client.post("/auth/logout", headers=me)).status_code == 204
    again = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert again.status_code == 401


async def test_concurrent_refresh_only_one_wins(client: httpx.AsyncClient) -> None:
    acct = await register(client, "race@example.com")
    results = await asyncio.gather(
        *[client.post("/auth/refresh", json={"refresh_token": acct.refresh}) for _ in range(3)]
    )
    assert sorted(r.status_code for r in results).count(200) == 1


async def test_logout_revokes_refresh(client: httpx.AsyncClient) -> None:
    acct = await register(client, "out@example.com")
    assert (await client.post("/auth/logout", headers=acct.h)).status_code == 204
    r = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert r.status_code == 401


async def test_sessions_list_and_revoke(client: httpx.AsyncClient) -> None:
    acct = await register(client, "multi@example.com")
    other = (
        await client.post("/auth/login", json={"email": acct.email, "password": PASSWORD})
    ).json()
    sessions = (await client.get("/me/sessions", headers=acct.h)).json()
    assert len(sessions) == 2
    assert [s["current"] for s in sessions].count(True) == 1

    r = await client.delete(f"/me/sessions/{other['session_id']}", headers=acct.h)
    assert r.status_code == 204
    r = await client.post("/auth/refresh", json={"refresh_token": other["refresh_token"]})
    assert r.status_code == 401
    assert len((await client.get("/me/sessions", headers=acct.h)).json()) == 1


async def test_password_change_signs_out_everywhere(client: httpx.AsyncClient) -> None:
    acct = await register(client, "pw@example.com")
    await asyncio.sleep(1.05)  # ensure the old token's iat is in an earlier second
    r = await client.post(
        "/me/password",
        json={"current_password": PASSWORD, "new_password": "a-brand-new-passphrase"},
        headers=acct.h,
    )
    assert r.status_code == 200
    fresh = r.json()

    assert (await client.get("/me", headers=acct.h)).status_code == 401  # old access token
    old_refresh = await client.post("/auth/refresh", json={"refresh_token": acct.refresh})
    assert old_refresh.status_code == 401
    me = await client.get("/me", headers={"Authorization": f"Bearer {fresh['access_token']}"})
    assert me.status_code == 200

    login_old = await client.post("/auth/login", json={"email": acct.email, "password": PASSWORD})
    assert login_old.status_code == 401


async def test_password_change_requires_current_password(client: httpx.AsyncClient) -> None:
    acct = await register(client, "pw2@example.com")
    r = await client.post(
        "/me/password",
        json={"current_password": "wrong-password", "new_password": "a-brand-new-passphrase"},
        headers=acct.h,
    )
    assert r.status_code == 401


async def test_update_profile_and_register_device(client: httpx.AsyncClient) -> None:
    acct = await register(client, "prof@example.com")
    r = await client.patch(
        "/me", json={"display_name": "New Name", "theme_pref": "dark"}, headers=acct.h
    )
    assert r.status_code == 200
    assert r.json()["display_name"] == "New Name"
    assert r.json()["theme_pref"] == "dark"

    device = {"platform": "ios", "fcm_token": "fcm-token-abcdef-123", "app_version": "1.0.0"}
    first = await client.post("/me/devices", json=device, headers=acct.h)
    again = await client.post("/me/devices", json=device, headers=acct.h)
    assert first.status_code == again.status_code == 201
    assert first.json()["id"] == again.json()["id"]  # idempotent upsert


async def test_problem_json_has_request_id(client: httpx.AsyncClient) -> None:
    r = await client.get("/me", headers={"X-Request-ID": "req-12345678"})
    assert problem(r)["request_id"] == "req-12345678"
    assert r.headers["x-request-id"] == "req-12345678"

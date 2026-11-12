"""Phase 6 security review: response hardening, body size limits, abuse rate limits."""

from collections.abc import AsyncIterator, Iterator

import httpx
import pytest

from app.core.config import get_settings
from tests.helpers import create_org, problem, register


@pytest.fixture
def limits() -> Iterator[None]:
    """Restore any limits a test lowers (settings are a cached singleton)."""
    s = get_settings()
    saved = s.model_dump()
    yield
    for k, v in saved.items():
        setattr(s, k, v)


async def test_api_responses_are_hardened(client: httpx.AsyncClient) -> None:
    owner = await register(client, "headers@example.com")
    r = await client.get("/me", headers=owner.h)
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["referrer-policy"] == "no-referrer"
    assert "default-src 'none'" in r.headers["content-security-policy"]
    assert r.headers["cache-control"] == "no-store"  # personal data is never cached
    assert "strict-transport-security" not in r.headers  # local/test: no HTTPS
    health = await client.get("http://test/healthz")
    assert health.headers["x-content-type-options"] == "nosniff"


async def test_oversized_bodies_are_rejected_before_parsing(client: httpx.AsyncClient) -> None:
    big = b'{"name": "' + b"x" * 1_100_000 + b'"}'
    r = await client.post("/orgs", content=big, headers={"content-type": "application/json"})
    assert r.status_code == 413 and problem(r)["code"] == "request.too_large"

    async def chunks() -> AsyncIterator[bytes]:  # no Content-Length: counted while reading
        for _ in range(12):
            yield b"x" * 100_000

    r = await client.post("/orgs", content=chunks(), headers={"content-type": "application/json"})
    assert r.status_code == 413

    # Ingestion gets a larger allowance (batches of points): this reaches auth, not the limit.
    r = await client.post(
        "http://test/ingest/v1/metrics",
        content=b'{"points": [], "pad": "' + b"x" * 2_000_000 + b'"}',
        headers={"content-type": "application/json", "authorization": "Bearer dp_ingest_nope"},
    )
    assert r.status_code == 401


async def test_registration_is_rate_limited_per_ip(client: httpx.AsyncClient, limits: None) -> None:
    get_settings().register_rate_limit_per_hour = 2
    await register(client, "ip1@example.com")
    await register(client, "ip2@example.com")
    r = await client.post(
        "/auth/register",
        json={
            "email": "ip3@example.com",
            "password": "a-long-enough-password",
            "display_name": "X",
        },
    )
    assert r.status_code == 429 and int(r.headers["retry-after"]) > 0


async def test_password_changes_are_rate_limited(client: httpx.AsyncClient, limits: None) -> None:
    get_settings().password_change_rate_limit = 2
    u = await register(client, "pw@example.com")
    body = {"current_password": "wrong-password", "new_password": "another-long-password"}
    codes = [
        (await client.post("/me/password", json=body, headers=u.h)).status_code for _ in range(3)
    ]
    assert codes == [401, 401, 429]  # guessing the current password is capped


async def test_invitations_are_rate_limited_per_org(
    client: httpx.AsyncClient, limits: None
) -> None:
    get_settings().invitation_rate_limit_per_hour = 2
    owner = await register(client, "inv-owner@example.com")
    org = await create_org(client, owner)
    codes = [
        (
            await client.post(
                f"/orgs/{org}/invitations",
                json={"email": f"p{i}@example.com", "role": "viewer"},
                headers=owner.h,
            )
        ).status_code
        for i in range(3)
    ]
    assert codes == [201, 201, 429]


async def test_ai_requests_are_rate_limited_per_user(
    client: httpx.AsyncClient, limits: None
) -> None:
    s = get_settings()
    s.ai_start_rate_limit = 1
    owner = await register(client, "ai-limit@example.com")
    org = await create_org(client, owner)
    url = f"/orgs/{org}/incidents/INC-1/investigations"
    first = await client.post(url, headers=owner.h)
    assert first.status_code != 429  # (404: no such incident — still counted)
    second = await client.post(url, headers=owner.h)
    assert second.status_code == 429


async def _register_from(client: httpx.AsyncClient, email: str, headers: dict[str, str]) -> int:
    r = await client.post(
        "/auth/register",
        json={"email": email, "password": "a-long-enough-password", "display_name": "X"},
        headers=headers,
    )
    return r.status_code


async def test_bff_forwarded_ip_needs_the_shared_secret(
    client: httpx.AsyncClient, limits: None
) -> None:
    from pydantic import SecretStr

    s = get_settings()
    s.register_rate_limit_per_hour = 1
    s.bff_shared_secret = SecretStr("bff-secret-for-tests-only")
    good = {"x-devpulse-bff-secret": "bff-secret-for-tests-only"}
    # Two different browsers behind the BFF: separate limits.
    assert (
        await _register_from(
            client, "b1@example.com", {**good, "x-devpulse-client-ip": "198.51.100.1"}
        )
        == 201
    )
    assert (
        await _register_from(
            client, "b2@example.com", {**good, "x-devpulse-client-ip": "198.51.100.2"}
        )
        == 201
    )
    assert (
        await _register_from(
            client, "b3@example.com", {**good, "x-devpulse-client-ip": "198.51.100.2"}
        )
        == 429
    )
    # Without the secret the header is ignored (no picking your own IP): the TCP peer counts.
    forged = {"x-devpulse-client-ip": "198.51.100.77", "x-devpulse-bff-secret": "wrong"}
    assert await _register_from(client, "b4@example.com", forged) == 201
    assert (
        await _register_from(client, "b5@example.com", {"x-devpulse-client-ip": "198.51.100.78"})
        == 429
    )


async def test_only_proxy_appended_forwarded_for_entries_count(
    client: httpx.AsyncClient, limits: None
) -> None:
    s = get_settings()
    s.register_rate_limit_per_hour = 1
    s.trusted_proxy_hops = 1
    # The client prepends a fake address each time; the proxy-appended one stays the same.
    assert (
        await _register_from(client, "h1@example.com", {"x-forwarded-for": "1.1.1.1, 203.0.113.5"})
        == 201
    )
    assert (
        await _register_from(client, "h2@example.com", {"x-forwarded-for": "2.2.2.2, 203.0.113.5"})
        == 429
    )


async def test_login_is_limited_per_email_across_ips(
    client: httpx.AsyncClient, limits: None
) -> None:
    s = get_settings()
    s.login_email_rate_limit = 2
    s.trusted_proxy_hops = 1
    await register(client, "victim@example.com")
    codes = []
    for i in range(3):
        r = await client.post(
            "/auth/login",
            json={"email": "victim@example.com", "password": "guess-" + str(i)},
            headers={"x-forwarded-for": f"203.0.113.{i}"},  # a new IP every attempt
        )
        codes.append(r.status_code)
    assert codes == [401, 401, 429]


def test_error_reports_never_carry_secrets() -> None:
    from app.core.observability import scrub_event

    event = {
        "request": {
            "headers": {
                "Authorization": "Bearer abc",
                "Cookie": "dp_rt=x",
                "X-DevPulse-BFF-Secret": "s",
                "User-Agent": "ua",
            },
            "data": {"password": "hunter2"},
            "cookies": {"dp_rt": "x"},
            "query_string": "key=secret",
        },
        "user": {"email": "a@b.c"},
    }
    out = scrub_event(event)
    assert out["request"]["headers"]["Authorization"] == "[Filtered]"
    assert out["request"]["headers"]["X-DevPulse-BFF-Secret"] == "[Filtered]"
    assert out["request"]["headers"]["User-Agent"] == "ua"
    assert "data" not in out["request"] and "cookies" not in out["request"]
    assert out["request"]["query_string"] == "[Filtered]" and "user" not in out

"""Alert evaluation, deployments, GitHub webhooks, correlation and the overview."""

import hashlib
import hmac
import json
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import pytest

from app.core.db import get_sessionmaker
from app.core.redis import get_redis
from app.modules.alerts.evaluator import evaluate_all
from app.modules.telemetry.rollup import process_dirty
from tests.helpers import (
    Account,
    create_ingest_key,
    create_org,
    create_service,
    ingest_h,
    ingest_points,
    problem,
    register,
)


@pytest.fixture
async def env(client: httpx.AsyncClient) -> dict[str, Any]:
    owner = await register(client, "alert-owner@acme.dev", "Alex")
    org = await create_org(client, owner)
    svc = await create_service(
        client, org, owner, name="checkout", repo_url="https://github.com/acme/checkout"
    )
    key = await create_ingest_key(client, org, owner)
    return {"org": org, "owner": owner, "svc": svc, "key": key}


def latency_points(start: datetime, n: int, value: float) -> list[dict[str, Any]]:
    return [
        {
            "name": "http.server.duration_ms",
            "ts": (start + timedelta(seconds=i * 5)).isoformat(),
            "value": value,
        }
        for i in range(n)
    ]


async def evaluate(now: datetime) -> Any:
    async with get_sessionmaker()() as s:
        return await evaluate_all(s, now=now)


async def make_rule(client: httpx.AsyncClient, env: dict[str, Any], **kw: Any) -> dict[str, Any]:
    owner: Account = env["owner"]
    body = {
        "name": "High latency",
        "service_id": env["svc"]["id"],
        "metric": "http.server.duration_ms",
        "aggregation": "p95",
        "comparator": "gt",
        "threshold": 500,
        "window_s": 300,
        "for_s": 60,
        "severity": "sev2",
        **kw,
    }
    r = await client.post(f"/orgs/{env['org']}/alert-rules", json=body, headers=owner.h)
    assert r.status_code == 201, r.text
    result: dict[str, Any] = r.json()
    return result


async def test_rule_validation(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    owner: Account = env["owner"]
    base = {
        "name": "x",
        "service_id": env["svc"]["id"],
        "comparator": "gt",
        "threshold": 1,
        "severity": "sev3",
    }
    bad = await client.post(
        f"/orgs/{env['org']}/alert-rules",
        json={**base, "metric": "cpu", "aggregation": "ratio"},
        headers=owner.h,
    )
    assert bad.status_code == 422
    ok = await client.post(
        f"/orgs/{env['org']}/alert-rules",
        json={**base, "metric": "http.server.error_rate", "aggregation": "ratio"},
        headers=owner.h,
    )
    assert ok.status_code == 201
    too_short = await client.post(
        f"/orgs/{env['org']}/alert-rules",
        json={**base, "metric": "cpu", "aggregation": "avg", "window_s": 10},
        headers=owner.h,
    )
    assert too_short.status_code == 422


async def test_alert_lifecycle_opens_incident_with_deploy_correlation(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    owner: Account = env["owner"]
    org = env["org"]
    rule = await make_rule(client, env)
    # Simulated clock in the past: ingestion only accepts points up to 5 min in the future,
    # so the whole scenario (spike → recovery → relapse) is replayed from 40 min ago.
    now = datetime.now(UTC) - timedelta(minutes=40)

    # A deploy 20 minutes earlier, sent by CI.
    dep = await client.post(
        "http://test/ingest/v1/deployments",
        json={
            "service": "checkout",
            "version": "v2.14.0",
            "external_id": "run-77",
            "commit_sha": "abc123",
            "started_at": (now - timedelta(minutes=20)).isoformat(),
            "status": "succeeded",
        },
        headers=ingest_h(env["key"]),
    )
    assert dep.status_code == 202, dep.text

    # Healthy traffic, then a latency spike.
    healthy = await ingest_points(
        client, env["key"], "checkout", latency_points(now - timedelta(minutes=4), 30, 120)
    )
    assert healthy.status_code == 202
    assert (await evaluate(now)).fired == 0

    await ingest_points(
        client, env["key"], "checkout", latency_points(now - timedelta(seconds=150), 30, 1400)
    )
    s1 = await evaluate(now)
    assert s1.fired == 0  # pending: must hold for 60s
    r = (await client.get(f"/orgs/{org}/alert-rules/{rule['id']}", headers=owner.h)).json()
    assert r["state"] == "pending"

    s2 = await evaluate(now + timedelta(seconds=61))
    assert (s2.fired, s2.incidents_opened) == (1, 1)

    incidents = (await client.get(f"/orgs/{org}/incidents", headers=owner.h)).json()["items"]
    assert len(incidents) == 1
    inc = incidents[0]
    assert inc["source"] == "alert" and inc["severity"] == "sev2"
    assert inc["title"] == "High latency on checkout"
    assert "p95 of http.server.duration_ms" in inc["summary"]

    correlated = (
        await client.get(f"/orgs/{org}/incidents/{inc['id']}/deployments", headers=owner.h)
    ).json()
    assert len(correlated) == 1
    assert correlated[0]["version"] == "v2.14.0"
    assert 0.8 < correlated[0]["score"] < 0.9  # 20 min of a 2 h lookback
    assert correlated[0]["correlation"] == "suspected"

    svc = (await client.get(f"/orgs/{org}/services/{env['svc']['id']}", headers=owner.h)).json()
    assert svc["health"] == "critical"  # firing sev2

    # Still breaching: no duplicate incident.
    s3 = await evaluate(now + timedelta(seconds=90))
    assert s3.incidents_opened == 0

    # Recovery: alert resolves, the incident stays open for a human to resolve.
    later = now + timedelta(minutes=10)
    recovered = await ingest_points(
        client, env["key"], "checkout", latency_points(later - timedelta(minutes=4), 40, 100)
    )
    assert recovered.status_code == 202
    s4 = await evaluate(later)
    assert s4.resolved == 1
    inc_after = (await client.get(f"/orgs/{org}/incidents/{inc['id']}", headers=owner.h)).json()
    assert inc_after["status"] == "triggered"
    types = [
        e["type"]
        for e in (
            await client.get(f"/orgs/{org}/incidents/{inc['id']}/timeline", headers=owner.h)
        ).json()["items"]
    ]
    assert types == ["created", "deployment_correlated", "alert_resolved"]
    svc = (await client.get(f"/orgs/{org}/services/{env['svc']['id']}", headers=owner.h)).json()
    assert svc["health"] == "healthy"

    # The same rule breaching again attaches to the still-open incident (dedup).
    again = later + timedelta(minutes=10)
    relapse = await ingest_points(
        client, env["key"], "checkout", latency_points(again - timedelta(minutes=2), 20, 2000)
    )
    assert relapse.status_code == 202
    await evaluate(again)
    s6 = await evaluate(again + timedelta(seconds=61))
    assert (s6.fired, s6.incidents_opened) == (1, 0)
    types = [
        e["type"]
        for e in (
            await client.get(f"/orgs/{org}/incidents/{inc['id']}/timeline", headers=owner.h)
        ).json()["items"]
    ]
    assert types[-1] == "alert_attached"


async def test_no_data_does_not_resolve_or_fire(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    await make_rule(client, env, for_s=0)
    now = datetime.now(UTC)
    stats = await evaluate(now)
    assert stats.no_data == 1 and stats.fired == 0
    svc = (
        await client.get(f"/orgs/{env['org']}/services/{env['svc']['id']}", headers=env["owner"].h)
    ).json()
    assert svc["health"] == "unknown"


async def test_error_rate_rule(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    await make_rule(
        client,
        env,
        name="Errors",
        metric="http.server.error_rate",
        aggregation="ratio",
        threshold=0.05,
        for_s=0,
        severity="sev3",
    )
    now = datetime.now(UTC)
    ts = (now - timedelta(minutes=1)).isoformat()
    await ingest_points(
        client,
        env["key"],
        "checkout",
        [
            {"name": "http.server.requests", "ts": ts, "value": 1000},
            {"name": "http.server.errors", "ts": ts, "value": 120},
        ],
    )
    stats = await evaluate(now)
    assert stats.fired == 1
    svc = (
        await client.get(f"/orgs/{env['org']}/services/{env['svc']['id']}", headers=env["owner"].h)
    ).json()
    assert svc["health"] == "degraded"  # sev3 firing


async def test_rule_preview(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    rule = await make_rule(client, env)
    now = datetime.now(UTC)
    await ingest_points(
        client, env["key"], "checkout", latency_points(now - timedelta(minutes=3), 20, 900)
    )
    r = await client.post(
        f"/orgs/{env['org']}/alert-rules/{rule['id']}/preview",
        params={"hours": 1},
        headers=env["owner"].h,
    )
    assert r.status_code == 200
    body = r.json()
    assert len(body["points"]) == 13
    assert body["breach_windows"] == 1
    assert body["points"][0]["value"] is None  # no data → gap, not zero


async def test_draft_preview_stores_nothing_and_is_tenant_scoped(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    now = datetime.now(UTC)
    await ingest_points(
        client, env["key"], "checkout", latency_points(now - timedelta(minutes=3), 20, 900)
    )
    draft = {
        "name": "Draft",
        "service_id": env["svc"]["id"],
        "metric": "http.server.duration_ms",
        "aggregation": "p95",
        "comparator": "gt",
        "threshold": 500,
        "window_s": 300,
        "for_s": 0,
        "severity": "sev3",
    }
    url = f"/orgs/{env['org']}/alert-rules/preview"
    r = await client.post(url, params={"hours": 1}, json=draft, headers=env["owner"].h)
    assert r.status_code == 200, r.text
    assert len(r.json()["points"]) == 13 and r.json()["breach_windows"] == 1
    # A higher threshold never breaches.
    r = await client.post(
        url, params={"hours": 1}, json={**draft, "threshold": 5000}, headers=env["owner"].h
    )
    assert r.json()["breach_windows"] == 0
    rules = await client.get(f"/orgs/{env['org']}/alert-rules", headers=env["owner"].h)
    assert rules.json() == []  # nothing stored
    # Same validation as creating a rule.
    bad = await client.post(url, json={**draft, "aggregation": "ratio"}, headers=env["owner"].h)
    assert bad.status_code == 422
    # Another org's service is not found, not previewed.
    other = await register(client, "preview-other@example.com")
    other_org = await create_org(client, other, "Other")
    r = await client.post(f"/orgs/{other_org}/alert-rules/preview", json=draft, headers=other.h)
    assert r.status_code == 404


async def test_deployment_ingest_is_idempotent(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    payload = {
        "service": "checkout",
        "version": "v1",
        "external_id": "build-1",
        "status": "started",
    }
    a = await client.post(
        "http://test/ingest/v1/deployments", json=payload, headers=ingest_h(env["key"])
    )
    b = await client.post(
        "http://test/ingest/v1/deployments",
        json={**payload, "status": "failed"},
        headers=ingest_h(env["key"]),
    )
    assert a.json()["id"] == b.json()["id"]
    listing = (await client.get(f"/orgs/{env['org']}/deployments", headers=env["owner"].h)).json()[
        "items"
    ]
    assert len(listing) == 1
    assert listing[0]["status"] == "failed"
    assert listing[0]["service_name"] == "checkout"


def _sign(secret: str, body: bytes) -> str:
    return "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


async def test_github_webhook(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    owner: Account = env["owner"]
    created = await client.post(
        f"/orgs/{env['org']}/integrations", json={"name": "GitHub"}, headers=owner.h
    )
    assert created.status_code == 201, created.text
    integ = created.json()
    secret = integ["webhook_secret"]
    listed = (await client.get(f"/orgs/{env['org']}/integrations", headers=owner.h)).json()
    assert "webhook_secret" not in listed[0] and "secret_encrypted" not in listed[0]

    url = f"http://test{integ['webhook_path']}"
    deployment = {
        "id": 991,
        "sha": "deadbeef",
        "ref": "v3.0.0",
        "environment": "production",
        "description": "Release 3",
        "creator": {"login": "octo"},
        "created_at": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    repo = {"full_name": "acme/checkout", "html_url": "https://github.com/acme/checkout"}

    async def send(
        event: str, payload: dict[str, Any], delivery: str, sign: bool = True
    ) -> httpx.Response:
        body = json.dumps(payload).encode()
        headers = {
            "X-GitHub-Event": event,
            "X-GitHub-Delivery": delivery,
            "Content-Type": "application/json",
        }
        if sign:
            headers["X-Hub-Signature-256"] = _sign(secret, body)
        return await client.post(url, content=body, headers=headers)

    bad = await send(
        "deployment", {"deployment": deployment, "repository": repo}, "d-0", sign=False
    )
    assert bad.status_code == 401
    assert problem(bad)["code"] == "webhook.invalid_signature"

    assert (await send("ping", {"zen": "hi"}, "d-1")).json() == {"status": "pong"}
    r = await send("deployment", {"deployment": deployment, "repository": repo}, "d-2")
    assert r.json() == {"status": "processed"}
    assert (
        await send("deployment", {"deployment": deployment, "repository": repo}, "d-2")
    ).json() == {"status": "duplicate"}
    r = await send(
        "deployment_status",
        {"deployment": deployment, "repository": repo, "deployment_status": {"state": "success"}},
        "d-3",
    )
    assert r.json() == {"status": "processed"}
    # A late/replayed `deployment` event must not move it back to "started".
    await send("deployment", {"deployment": deployment, "repository": repo}, "d-4")

    deps = (await client.get(f"/orgs/{env['org']}/deployments", headers=owner.h)).json()["items"]
    assert len(deps) == 1
    assert deps[0]["source"] == "github"
    assert deps[0]["status"] == "succeeded"
    assert deps[0]["version"] == "v3.0.0"
    assert deps[0]["commit_author"] == "octo"

    other_repo = {"full_name": "acme/unknown", "html_url": "https://github.com/acme/unknown"}
    r = await send(
        "deployment", {"deployment": {**deployment, "id": 5}, "repository": other_repo}, "d-5"
    )
    assert r.json() == {"status": "unmapped_repository"}
    r = await send("deployment", {"nonsense": True}, "d-6")
    assert r.json() == {"status": "error"}

    unknown = await client.post(
        f"http://test/webhooks/github/{uuid.uuid4()}",
        content=b"{}",
        headers={
            "X-GitHub-Event": "ping",
            "X-GitHub-Delivery": "x",
            "X-Hub-Signature-256": "sha256=00",
        },
    )
    assert unknown.status_code == 401


async def test_overview(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    owner: Account = env["owner"]
    now = datetime.now(UTC)
    ts = (now - timedelta(minutes=2)).isoformat()
    await ingest_points(
        client,
        env["key"],
        "checkout",
        [
            {"name": "http.server.requests", "ts": ts, "value": 200},
            {"name": "http.server.errors", "ts": ts, "value": 4},
            {"name": "http.server.duration_ms", "ts": ts, "value": 100},
            {"name": "http.server.duration_ms", "ts": ts, "value": 300},
        ],
    )
    async with get_sessionmaker()() as s:
        await process_dirty(s, get_redis())
    await client.post(
        f"/orgs/{env['org']}/incidents",
        json={"title": "Manual one", "severity": "sev1"},
        headers=owner.h,
    )

    o = (
        await client.get(f"/orgs/{env['org']}/overview", params={"window": "1h"}, headers=owner.h)
    ).json()
    assert o["services_total"] == 1
    assert o["open_incidents_by_severity"]["sev1"] == 1
    assert o["totals"]["requests"] == 200
    assert o["totals"]["error_rate"] == pytest.approx(0.02)
    assert o["totals"]["latency_avg_ms"] == pytest.approx(200)
    assert o["has_telemetry"] is True
    assert sum(v for _, v in o["request_series"] if v) == 200
    assert [i["title"] for i in o["recent_incidents"]] == ["Manual one"]

    empty_owner = await register(client, "empty@acme.dev")
    empty_org = await create_org(client, empty_owner, "Empty")
    e = (await client.get(f"/orgs/{empty_org}/overview", headers=empty_owner.h)).json()
    assert e["has_telemetry"] is False
    assert e["totals"]["requests"] is None  # no data is not zero

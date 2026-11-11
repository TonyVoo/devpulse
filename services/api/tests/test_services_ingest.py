from datetime import UTC, datetime, timedelta

import httpx
import pytest

from app.core.db import get_sessionmaker
from app.core.redis import get_redis
from app.modules.telemetry.ingest import log_fingerprint
from app.modules.telemetry.rollup import maintain_partitions, process_dirty
from tests.helpers import (
    Account,
    add_member,
    create_ingest_key,
    create_org,
    create_service,
    ingest_h,
    ingest_points,
    problem,
    register,
)


@pytest.fixture
async def org(client: httpx.AsyncClient) -> dict[str, object]:
    owner = await register(client, "svc-owner@acme.dev")
    viewer = await register(client, "svc-viewer@acme.dev")
    org_id = await create_org(client, owner)
    await add_member(client, org_id, owner, viewer, "viewer")
    return {"id": org_id, "owner": owner, "viewer": viewer}


def now() -> datetime:
    return datetime.now(UTC)


# --------------------------------------------------------------------- services


async def test_service_crud_and_conflicts(
    client: httpx.AsyncClient, org: dict[str, object]
) -> None:
    oid, owner, viewer = org["id"], org["owner"], org["viewer"]
    assert isinstance(owner, Account) and isinstance(viewer, Account)
    svc = await create_service(
        client, str(oid), owner, repo_url="https://github.com/acme/checkout/"
    )
    assert svc["slug"] == "checkout-api"
    assert svc["health"] == "unknown"
    assert svc["repo_url"] == "https://github.com/acme/checkout"

    dup = await client.post(f"/orgs/{oid}/services", json={"name": "Checkout API"}, headers=owner.h)
    assert dup.status_code == 409
    assert problem(dup)["code"] == "service.slug_taken"
    other_env = await client.post(
        f"/orgs/{oid}/services",
        json={"name": "Checkout API", "environment": "staging"},
        headers=owner.h,
    )
    assert other_env.status_code == 201

    r = await client.post(f"/orgs/{oid}/services", json={"name": "Nope"}, headers=viewer.h)
    assert r.status_code == 403

    # Optimistic concurrency
    url = f"/orgs/{oid}/services/{svc['id']}"
    stale = await client.patch(
        url, json={"name": "Checkout"}, headers={**owner.h, "If-Match": '"99"'}
    )
    assert stale.status_code == 409
    assert problem(stale)["code"] == "conflict.version_mismatch"
    ok = await client.patch(url, json={"name": "Checkout"}, headers={**owner.h, "If-Match": '"1"'})
    assert ok.status_code == 200
    assert ok.json()["version"] == 2
    assert ok.headers["etag"] == '"2"'

    listing = (
        await client.get(f"/orgs/{oid}/services", params={"q": "check"}, headers=viewer.h)
    ).json()
    assert [s["name"] for s in listing["items"]] == ["Checkout", "Checkout API"]

    assert (await client.delete(url, headers=owner.h)).status_code == 204
    assert (await client.get(url, headers=owner.h)).status_code == 404
    # Slug is free again after deletion.
    assert (
        await client.post(f"/orgs/{oid}/services", json={"name": "Checkout API"}, headers=owner.h)
    ).status_code == 201


async def test_service_list_pagination(client: httpx.AsyncClient, org: dict[str, object]) -> None:
    oid, owner = str(org["id"]), org["owner"]
    assert isinstance(owner, Account)
    for n in ["alpha", "bravo", "charlie", "delta", "echo"]:
        await create_service(client, oid, owner, name=n)
    seen, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        body = (await client.get(f"/orgs/{oid}/services", params=params, headers=owner.h)).json()
        seen += [s["name"] for s in body["items"]]
        cursor = body["next_cursor"]
        if not cursor:
            break
    assert seen == ["alpha", "bravo", "charlie", "delta", "echo"]


# --------------------------------------------------------------------- ingestion


async def test_ingest_metrics_happy_path_and_rollup(
    client: httpx.AsyncClient, org: dict[str, object]
) -> None:
    oid, owner = str(org["id"]), org["owner"]
    assert isinstance(owner, Account)
    svc = await create_service(client, oid, owner, name="api")
    key = await create_ingest_key(client, oid, owner)
    minute = now().replace(second=5, microsecond=0) - timedelta(minutes=1)
    points = [
        {
            "name": "http.server.duration_ms",
            "ts": (minute + timedelta(seconds=i)).isoformat(),
            "value": v,
        }
        for i, v in enumerate([100, 200, 300, 400, 1000])
    ] + [
        {"name": "http.server.requests", "ts": minute.isoformat(), "value": 50},
        {"name": "http.server.errors", "ts": minute.isoformat(), "value": 5},
    ]
    r = await ingest_points(client, key, "api", points)
    assert r.status_code == 202, r.text
    assert r.json() == {"accepted": 7, "service_id": svc["id"]}

    async with get_sessionmaker()() as s:
        assert await process_dirty(s, get_redis()) == 1  # one (service, minute)

    m = await client.get(
        f"/orgs/{oid}/services/{svc['id']}/metrics",
        params={
            "names": [
                "http.server.duration_ms:max",
                "http.server.duration_ms:avg",
                "http.server.error_rate",
                "http.server.requests:sum",
            ]
        },
        headers=owner.h,
    )
    assert m.status_code == 200, m.text
    series = {(s["name"], s["aggregation"]): s["points"] for s in m.json()["series"]}
    assert series[("http.server.duration_ms", "max")][0][1] == 1000
    assert series[("http.server.duration_ms", "avg")][0][1] == 400
    assert series[("http.server.error_rate", "ratio")][0][1] == pytest.approx(0.1)
    assert series[("http.server.requests", "sum")][0][1] == 50

    svc_after = (await client.get(f"/orgs/{oid}/services/{svc['id']}", headers=owner.h)).json()
    assert svc_after["last_seen_at"] is not None


async def test_ingest_rejections(client: httpx.AsyncClient, org: dict[str, object]) -> None:
    oid, owner = str(org["id"]), org["owner"]
    assert isinstance(owner, Account)
    await create_service(client, oid, owner, name="api")
    other = await create_service(client, oid, owner, name="worker")
    point = [{"name": "cpu", "ts": now().isoformat(), "value": 0.5}]

    assert (await ingest_points(client, "dp_ingest_nope", "api", point)).status_code == 401
    r = await client.post("http://test/ingest/v1/metrics", json={"service": "api", "points": point})
    assert r.status_code == 401

    logs_only = await create_ingest_key(client, oid, owner, scopes=["logs:write"])
    r = await ingest_points(client, logs_only, "api", point)
    assert r.status_code == 403
    assert problem(r)["code"] == "ingest.scope_missing"

    key = await create_ingest_key(client, oid, owner)
    r = await ingest_points(client, key, "ghost", point)
    assert r.status_code == 422
    assert problem(r)["code"] == "ingest.unknown_service"

    old = [{"name": "cpu", "ts": (now() - timedelta(hours=2)).isoformat(), "value": 1}]
    r = await ingest_points(client, key, "api", old)
    assert problem(r)["code"] == "ingest.timestamp_out_of_range"
    naive = [{"name": "cpu", "ts": "2026-11-11T10:00:00", "value": 1}]
    assert (
        problem(await ingest_points(client, key, "api", naive))["code"] == "ingest.naive_timestamp"
    )
    bad_value = [{"name": "cpu", "ts": now().isoformat(), "value": "NaN"}]
    assert (await ingest_points(client, key, "api", bad_value)).status_code == 422

    bound = await create_ingest_key(client, oid, owner, service_id=other["id"])
    r = await ingest_points(client, bound, "api", point)
    assert problem(r)["code"] == "ingest.wrong_service"
    assert (await ingest_points(client, bound, "worker", point)).status_code == 202

    keys = (await client.get(f"/orgs/{oid}/ingest-keys", headers=owner.h)).json()
    target = next(k for k in keys if k["service_id"] == other["id"])
    assert "key" not in target and target["prefix"].startswith("dp_ingest")
    assert (
        await client.delete(f"/orgs/{oid}/ingest-keys/{target['id']}", headers=owner.h)
    ).status_code == 204
    assert (await ingest_points(client, bound, "worker", point)).status_code == 401


async def test_autocreate_scope(client: httpx.AsyncClient, org: dict[str, object]) -> None:
    oid, owner = str(org["id"]), org["owner"]
    assert isinstance(owner, Account)
    key = await create_ingest_key(
        client, oid, owner, scopes=["metrics:write", "services:autocreate"]
    )
    r = await ingest_points(
        client, key, "new-svc", [{"name": "cpu", "ts": now().isoformat(), "value": 1}]
    )
    assert r.status_code == 202
    names = [
        s["slug"]
        for s in (await client.get(f"/orgs/{oid}/services", headers=owner.h)).json()["items"]
    ]
    assert names == ["new-svc"]


async def test_ingest_key_cannot_reach_other_org(
    client: httpx.AsyncClient, org: dict[str, object]
) -> None:
    owner = org["owner"]
    assert isinstance(owner, Account)
    mallory = await register(client, "mallory@evil.dev")
    evil_org = await create_org(client, mallory, "Evil")
    await create_service(client, evil_org, mallory, name="api")
    await create_service(client, str(org["id"]), owner, name="api")
    evil_key = await create_ingest_key(client, evil_org, mallory)
    # Same slug exists in both orgs; the key resolves to its own org only.
    r = await ingest_points(
        client, evil_key, "api", [{"name": "cpu", "ts": now().isoformat(), "value": 1}]
    )
    assert r.status_code == 202
    victim_service = (await client.get(f"/orgs/{org['id']}/services", headers=owner.h)).json()[
        "items"
    ][0]
    assert r.json()["service_id"] != victim_service["id"]


async def test_ingest_logs_and_fingerprints(
    client: httpx.AsyncClient, org: dict[str, object]
) -> None:
    oid, owner = str(org["id"]), org["owner"]
    assert isinstance(owner, Account)
    await create_service(client, oid, owner, name="api")
    key = await create_ingest_key(client, oid, owner)
    r = await client.post(
        "http://test/ingest/v1/logs",
        json={
            "service": "api",
            "logs": [
                {"ts": now().isoformat(), "level": "error", "message": "DB timeout after 3012ms"},
                {"ts": now().isoformat(), "level": "warning", "message": "slow query"},
            ],
        },
        headers=ingest_h(key),
    )
    assert r.status_code == 202, r.text
    assert log_fingerprint("error", "DB timeout after 3012ms") == log_fingerprint(
        "error", "db timeout after 5004ms"
    )
    assert log_fingerprint("error", "a") != log_fingerprint("warn", "a")


async def test_partition_maintenance_is_idempotent() -> None:
    async with get_sessionmaker()() as s:
        first = await maintain_partitions(s)
        second = await maintain_partitions(s)
    assert second["created"] == 0
    assert first["dropped"] == 0 and second["dropped"] == 0

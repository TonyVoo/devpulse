"""Phase 3: sync feed, commit-ordered change_seq, outbox relay, push dispatch, WebSocket."""

import asyncio
import contextlib
import json
import os
import socket
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import asyncpg
import httpx
import pytest
import websockets

from app.core.db import get_sessionmaker
from app.core.redis import get_redis
from app.modules.notifications.push import RecordingPushProvider
from app.workers.relay import relay_once
from tests.helpers import (
    Account,
    add_member,
    create_ingest_key,
    create_org,
    create_service,
    ingest_points,
    register,
)

API_DIR = Path(__file__).resolve().parents[1]


@pytest.fixture
async def env(client: httpx.AsyncClient) -> dict[str, Any]:
    owner = await register(client, "sync-owner@acme.dev", "Olive")
    eng = await register(client, "sync-eng@acme.dev", "Eli")
    org = await create_org(client, owner)
    await add_member(client, org, owner, eng, "engineer")
    svc = await create_service(client, org, owner, name="checkout")
    return {"org": org, "owner": owner, "eng": eng, "svc": svc}


async def _sync(
    client: httpx.AsyncClient, env: dict[str, Any], coll: str, cursor: int = 0, limit: int = 500
) -> dict[str, Any]:
    r = await client.get(
        f"/orgs/{env['org']}/sync/{coll}",
        params={"cursor": cursor, "limit": limit},
        headers=env["owner"].h,
    )
    assert r.status_code == 200, r.text
    body: dict[str, Any] = r.json()
    return body


async def _incident(
    client: httpx.AsyncClient,
    env: dict[str, Any],
    title: str = "Broken checkout",
    sev: str = "sev2",
) -> dict[str, Any]:
    r = await client.post(
        f"/orgs/{env['org']}/incidents",
        json={"title": title, "severity": sev, "service_id": env["svc"]["id"]},
        headers=env["eng"].h,
    )
    assert r.status_code == 201, r.text
    body: dict[str, Any] = r.json()
    return body


# --------------------------------------------------------------------------- sync feed


async def test_delta_sync_returns_only_changes_after_cursor(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    a = await _incident(client, env, "First")
    b = await _incident(client, env, "Second")
    first = await _sync(client, env, "incidents")
    assert [c["data"]["title"] for c in first["changes"]] == ["First", "Second"]
    assert first["has_more"] is False
    cursor = first["next_cursor"]

    again = await _sync(client, env, "incidents", cursor)
    assert again["changes"] == [] and again["next_cursor"] == cursor  # nothing new

    await client.post(f"/orgs/{env['org']}/incidents/{a['id']}/acknowledge", headers=env["eng"].h)
    delta = await _sync(client, env, "incidents", cursor)
    assert [(c["id"], c["data"]["status"]) for c in delta["changes"]] == [(a["id"], "acknowledged")]
    assert delta["next_cursor"] > cursor
    assert b["id"] not in {c["id"] for c in delta["changes"]}


async def test_pagination_and_tombstones(client: httpx.AsyncClient, env: dict[str, Any]) -> None:
    for i in range(4):
        await create_service(client, env["org"], env["owner"], name=f"svc-{i}")
    page1 = await _sync(client, env, "services", 0, limit=2)
    assert page1["has_more"] is True and len(page1["changes"]) == 2
    page2 = await _sync(client, env, "services", page1["next_cursor"], limit=2)
    page3 = await _sync(client, env, "services", page2["next_cursor"], limit=2)
    names = [c["data"]["name"] for p in (page1, page2, page3) for c in p["changes"]]
    assert sorted(names) == sorted(["checkout", "svc-0", "svc-1", "svc-2", "svc-3"])
    assert page3["has_more"] is False

    await client.delete(f"/orgs/{env['org']}/services/{env['svc']['id']}", headers=env["owner"].h)
    delta = await _sync(client, env, "services", page3["next_cursor"])
    assert delta["changes"] == [
        {
            "op": "delete",
            "id": env["svc"]["id"],
            "change_seq": delta["changes"][0]["change_seq"],
            "data": None,
        }
    ]
    # A fresh client never sees deleted services.
    fresh = await _sync(client, env, "services")
    assert env["svc"]["id"] not in {c["id"] for c in fresh["changes"]}


async def test_initial_sync_skips_old_resolved_incidents(
    client: httpx.AsyncClient, env: dict[str, Any], db_dsn: str
) -> None:
    old = await _incident(client, env, "Ancient")
    await client.post(
        f"/orgs/{env['org']}/incidents/{old['id']}/resolve", json={}, headers=env["eng"].h
    )
    conn = await asyncpg.connect(db_dsn)
    try:
        await conn.execute(
            "UPDATE incidents SET resolved_at = now() - interval '30 days' WHERE id = $1", old["id"]
        )
    finally:
        await conn.close()
    await _incident(client, env, "Current")
    first = await _sync(client, env, "incidents")
    assert [c["data"]["title"] for c in first["changes"]] == ["Current"]
    # …but if the old incident changes later, it does arrive.
    await client.post(
        f"/orgs/{env['org']}/incidents/{old['id']}/reopen", json={}, headers=env["eng"].h
    )
    delta = await _sync(client, env, "incidents", first["next_cursor"])
    assert [c["data"]["title"] for c in delta["changes"]] == ["Ancient"]


async def test_ingestion_does_not_trigger_sync_or_outbox(
    client: httpx.AsyncClient, env: dict[str, Any], db_dsn: str
) -> None:
    key = await create_ingest_key(client, env["org"], env["owner"])
    before = await _sync(client, env, "services")
    conn = await asyncpg.connect(db_dsn)
    try:
        outbox_before = await conn.fetchval("SELECT count(*) FROM outbox")
        ts = datetime.now(UTC).isoformat()
        assert (
            await ingest_points(client, key, "checkout", [{"name": "cpu", "ts": ts, "value": 1}])
        ).status_code == 202
        assert await conn.fetchval("SELECT count(*) FROM outbox") == outbox_before
        assert await conn.fetchval(
            "SELECT last_seen_at IS NOT NULL FROM services WHERE id = $1", env["svc"]["id"]
        )
    finally:
        await conn.close()
    after = await _sync(client, env, "services", before["next_cursor"])
    assert after["changes"] == []


async def test_change_seq_follows_commit_order(
    client: httpx.AsyncClient, env: dict[str, Any], db_dsn: str
) -> None:
    """The sync invariant: within an org, a later commit never gets a smaller change_seq.
    A second writer in the same org blocks until the first commits."""
    a = await _incident(client, env, "Alpha")
    b = await _incident(client, env, "Bravo")
    other_owner = await register(client, "other@else.dev")
    other_org = await create_org(client, other_owner, "Else")
    other_svc = await create_service(client, other_org, other_owner, name="x")

    t1, t2, t3 = [await asyncpg.connect(db_dsn) for _ in range(3)]
    try:
        await t1.execute("BEGIN")
        seq1 = await t1.fetchval(
            "UPDATE incidents SET title = 'A2' WHERE id = $1 RETURNING change_seq", a["id"]
        )

        async def second_writer() -> int:
            await t2.execute("BEGIN")
            seq = await t2.fetchval(
                "UPDATE incidents SET title = 'B2' WHERE id = $1 RETURNING change_seq", b["id"]
            )
            await t2.execute("COMMIT")
            return int(seq)

        task = asyncio.create_task(second_writer())
        await asyncio.sleep(0.3)
        assert not task.done(), "same-org writer must wait for the first transaction"

        # Another org is not blocked.
        await asyncio.wait_for(
            t3.execute("UPDATE services SET name = 'y' WHERE id = $1", other_svc["id"]), timeout=2
        )

        await t1.execute("COMMIT")
        seq2 = await asyncio.wait_for(task, timeout=5)
        assert seq1 < seq2
    finally:
        for c in (t1, t2, t3):
            await c.close()


# --------------------------------------------------------------------------- outbox / relay / push


async def test_outbox_relay_publishes_hints_and_events(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    pubsub = get_redis().pubsub()
    await pubsub.subscribe(f"org:{env['org']}")
    await pubsub.get_message(timeout=1)  # subscribe confirmation
    inc = await _incident(client, env)
    push = RecordingPushProvider()
    async with get_sessionmaker()() as s:
        published = await relay_once(s, get_redis(), push)
        assert published >= 2
        assert await relay_once(s, get_redis(), push) == 0  # nothing left

    messages = []
    for _ in range(20):
        m = await pubsub.get_message(timeout=0.2)
        if m and m["type"] == "message":
            messages.append(json.loads(m["data"]))
    await pubsub.aclose()
    hints = [m for m in messages if m["type"] == "sync" and m["collection"] == "incidents"]
    assert hints and hints[-1]["id"] == inc["id"] and hints[-1]["change_seq"] > 0
    events = [m for m in messages if m["type"] == "incident_event"]
    assert events[0]["event"] == "created" and events[0]["incident_id"] == inc["id"]


async def _register_device(client: httpx.AsyncClient, who: Account, token: str) -> None:
    r = await client.post(
        "/me/devices", json={"platform": "ios", "fcm_token": token}, headers=who.h
    )
    assert r.status_code == 201


async def _relay(push: RecordingPushProvider) -> None:
    async with get_sessionmaker()() as s:
        while await relay_once(s, get_redis(), push):
            pass


async def test_push_recipients_follow_preferences(
    client: httpx.AsyncClient, env: dict[str, Any]
) -> None:
    owner, eng = env["owner"], env["eng"]
    await _register_device(client, owner, "token-owner-123")
    await _register_device(client, eng, "token-eng-12345")
    push = RecordingPushProvider()
    await _relay(push)  # drain setup events

    # Created by eng → only owner is notified (the actor never notifies themselves).
    inc = await _incident(client, env, "Checkout down", "sev2")
    await _relay(push)
    assert [m.tokens for m in push.sent] == [["token-owner-123"]]
    assert push.sent[0].data["route"] == f"/incidents/{inc['key']}"
    assert push.sent[0].title.startswith(f"[SEV2] {inc['key']}")

    # Below the default threshold (sev2): no push.
    push.sent.clear()
    await _incident(client, env, "Minor", "sev4")
    await _relay(push)
    assert push.sent == []

    # Owner opts into everything; sev4 now notifies them.
    r = await client.put(
        f"/orgs/{env['org']}/notification-preferences",
        json={"push_enabled": True, "min_severity": "sev4", "only_assigned": False},
        headers=owner.h,
    )
    assert r.status_code == 200
    assert (
        await client.get(f"/orgs/{env['org']}/notification-preferences", headers=owner.h)
    ).json()["min_severity"] == "sev4"
    await _incident(client, env, "Minor 2", "sev4")
    await _relay(push)
    assert [m.tokens for m in push.sent] == [["token-owner-123"]]

    # Assignment notifies exactly the assignee.
    push.sent.clear()
    await client.post(
        f"/orgs/{env['org']}/incidents/{inc['id']}/assign",
        json={"user_id": eng.id},
        headers=owner.h,
    )
    await _relay(push)
    assert [m.tokens for m in push.sent] == [["token-eng-12345"]]
    assert "assigned to you" in push.sent[0].title

    # Push disabled → nothing.
    push.sent.clear()
    await client.put(
        f"/orgs/{env['org']}/notification-preferences",
        json={"push_enabled": False, "min_severity": "sev4", "only_assigned": False},
        headers=owner.h,
    )
    await _incident(client, env, "Quiet", "sev1")
    await _relay(push)
    assert push.sent == []


# --------------------------------------------------------------------------- WebSocket


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture(scope="module")
def ws_server() -> Any:
    """Real uvicorn process against the test database (WebSockets need a real server)."""
    port = _free_port()
    proc = subprocess.Popen(  # noqa: S603 - fixed argv
        [
            sys.executable,
            "-m",
            "uvicorn",
            "app.main:app",
            "--port",
            str(port),
            "--log-level",
            "warning",
        ],
        cwd=API_DIR,
        env={**os.environ},
    )
    deadline = datetime.now() + timedelta(seconds=20)
    while datetime.now() < deadline:
        with (
            contextlib.suppress(OSError),
            socket.create_connection(("127.0.0.1", port), timeout=0.2),
        ):
            break
    yield port
    proc.terminate()
    proc.wait(timeout=10)


async def test_websocket_ticket_flow(
    client: httpx.AsyncClient, env: dict[str, Any], ws_server: int
) -> None:
    stranger = await register(client, "stranger@x.dev")
    denied = await client.post(
        "http://test/api/v1/realtime/ticket", json={"org_id": env["org"]}, headers=stranger.h
    )
    assert denied.status_code == 404

    r = await client.post(
        "http://test/api/v1/realtime/ticket", json={"org_id": env["org"]}, headers=env["eng"].h
    )
    assert r.status_code == 200
    ticket = r.json()["ticket"]
    url = f"ws://127.0.0.1:{ws_server}/ws?ticket={ticket}"

    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello["type"] == "hello" and hello["org_id"] == env["org"]
        await get_redis().publish(
            f"org:{env['org']}",
            json.dumps({"type": "sync", "collection": "incidents", "change_seq": 42}),
        )
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert msg == {"type": "sync", "collection": "incidents", "change_seq": 42}

    # Tickets are single use.
    async with websockets.connect(url) as ws:
        with pytest.raises(websockets.ConnectionClosed) as closed:
            await asyncio.wait_for(ws.recv(), timeout=5)
        assert closed.value.rcvd is not None and closed.value.rcvd.code == 4401

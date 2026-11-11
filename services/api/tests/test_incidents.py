import asyncio
import uuid

import httpx
import pytest

from tests.helpers import Account, add_member, create_org, create_service, problem, register


@pytest.fixture
async def team(client: httpx.AsyncClient) -> dict[str, object]:
    owner = await register(client, "inc-owner@acme.dev", "Olive Owner")
    eng = await register(client, "inc-eng@acme.dev", "Eli Engineer")
    viewer = await register(client, "inc-viewer@acme.dev", "Vic Viewer")
    org = await create_org(client, owner)
    await add_member(client, org, owner, eng, "engineer")
    await add_member(client, org, owner, viewer, "viewer")
    svc = await create_service(client, org, owner, name="payments")
    return {"org": org, "owner": owner, "eng": eng, "viewer": viewer, "svc": svc}


async def _create(
    client: httpx.AsyncClient,
    team: dict[str, object],
    title: str = "Checkout failing",
    **kw: object,
) -> dict[str, object]:
    eng = team["eng"]
    assert isinstance(eng, Account)
    r = await client.post(
        f"/orgs/{team['org']}/incidents",
        json={"title": title, "severity": "sev2", **kw},
        headers=eng.h,
    )
    assert r.status_code == 201, r.text
    body: dict[str, object] = r.json()
    return body


async def test_create_numbering_and_lookup_by_key(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    svc = team["svc"]
    assert isinstance(svc, dict)
    a = await _create(client, team, service_id=svc["id"])
    b = await _create(client, team, title="Second")
    assert (a["number"], b["number"]) == (1001, 1002)
    assert a["key"] == "INC-1001"
    assert a["status"] == "triggered"
    assert a["service"]["name"] == "payments"  # type: ignore[index]

    eng = team["eng"]
    assert isinstance(eng, Account)
    by_key = await client.get(f"/orgs/{team['org']}/incidents/inc-1001", headers=eng.h)
    assert by_key.status_code == 200
    assert by_key.json()["id"] == a["id"]
    assert by_key.headers["etag"] == '"1"'
    assert (
        await client.get(f"/orgs/{team['org']}/incidents/INC-9", headers=eng.h)
    ).status_code == 404
    assert (
        await client.get(f"/orgs/{team['org']}/incidents/garbage", headers=eng.h)
    ).status_code == 404


async def test_lifecycle_and_invalid_transitions(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    inc = await _create(client, team)
    eng, owner = team["eng"], team["owner"]
    assert isinstance(eng, Account) and isinstance(owner, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['key']}"

    ack = await client.post(f"{base}/acknowledge", headers=eng.h)
    assert ack.status_code == 200, ack.text
    assert ack.json()["status"] == "acknowledged"
    assert ack.json()["assignee"]["display_name"] == "Eli Engineer"  # ack takes ownership
    assert ack.headers["etag"] == '"2"'

    again = await client.post(f"{base}/acknowledge", headers=eng.h)
    assert again.status_code == 409
    assert problem(again)["code"] == "incident.invalid_transition"

    esc = await client.post(f"{base}/escalate", json={"reason": "customer impact"}, headers=eng.h)
    assert esc.json()["escalation_level"] == 1
    sev = await client.post(f"{base}/severity", json={"severity": "sev1"}, headers=eng.h)
    assert sev.json()["severity"] == "sev1"

    assign = await client.post(f"{base}/assign", json={"user_id": owner.id}, headers=eng.h)
    assert assign.json()["assignee"]["display_name"] == "Olive Owner"
    stranger = await register(client, "stranger@x.dev")
    bad = await client.post(f"{base}/assign", json={"user_id": stranger.id}, headers=eng.h)
    assert problem(bad)["code"] == "incident.assignee_not_member"

    res = await client.post(
        f"{base}/resolve",
        json={"resolution_note": "Rolled back", "root_cause": "Bad config"},
        headers=eng.h,
    )
    assert res.json()["status"] == "resolved"
    assert res.json()["root_cause_confirmed"] == "Bad config"
    for action, body in [("escalate", {}), ("assign", {"user_id": None}), ("resolve", {})]:
        r = await client.post(f"{base}/{action}", json=body, headers=eng.h)
        assert r.status_code == 409, action

    reopen = await client.post(f"{base}/reopen", json={"reason": "came back"}, headers=eng.h)
    assert reopen.json()["status"] == "triggered"
    assert reopen.json()["resolved_at"] is None

    timeline = (await client.get(f"{base}/timeline", headers=eng.h)).json()["items"]
    assert [e["type"] for e in timeline] == [
        "created",
        "acknowledged",
        "escalated",
        "severity_changed",
        "assigned",
        "resolved",
        "reopened",
    ]
    assert timeline[1]["actor"]["display_name"] == "Eli Engineer"


async def test_viewer_cannot_act(client: httpx.AsyncClient, team: dict[str, object]) -> None:
    inc = await _create(client, team)
    viewer = team["viewer"]
    assert isinstance(viewer, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['id']}"
    assert (await client.get(base, headers=viewer.h)).status_code == 200
    assert (await client.post(f"{base}/acknowledge", headers=viewer.h)).status_code == 403
    r = await client.post(
        f"/orgs/{team['org']}/incidents",
        json={"title": "x" * 5, "severity": "sev3"},
        headers=viewer.h,
    )
    assert r.status_code == 403


async def test_if_match_conflict_returns_current_version(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    inc = await _create(client, team)
    eng = team["eng"]
    assert isinstance(eng, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['id']}"
    await client.post(f"{base}/escalate", json={}, headers=eng.h)  # version → 2
    stale = await client.post(f"{base}/acknowledge", headers={**eng.h, "If-Match": '"1"'})
    assert stale.status_code == 409
    assert problem(stale)["code"] == "conflict.version_mismatch"
    assert problem(stale)["current_version"] == 2
    ok = await client.post(f"{base}/acknowledge", headers={**eng.h, "If-Match": '"2"'})
    assert ok.status_code == 200


async def test_idempotency_key_replays(client: httpx.AsyncClient, team: dict[str, object]) -> None:
    inc = await _create(client, team)
    eng = team["eng"]
    assert isinstance(eng, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['id']}"
    h = {**eng.h, "Idempotency-Key": "ack-123"}

    first = await client.post(f"{base}/acknowledge", headers=h)
    replay = await client.post(f"{base}/acknowledge", headers=h)  # would be 409 without the key
    assert first.status_code == replay.status_code == 200
    assert replay.json() == first.json()
    assert replay.headers["idempotent-replayed"] == "true"

    reused = await client.post(f"{base}/escalate", json={}, headers=h)
    assert reused.status_code == 422
    assert problem(reused)["code"] == "idempotency.key_reused"

    # Creating incidents is idempotent too (mobile offline outbox).
    hc = {**eng.h, "Idempotency-Key": "create-1"}
    body = {"title": "Offline created", "severity": "sev3"}
    c1 = await client.post(f"/orgs/{team['org']}/incidents", json=body, headers=hc)
    c2 = await client.post(f"/orgs/{team['org']}/incidents", json=body, headers=hc)
    assert c1.status_code == c2.status_code == 201
    assert c1.json()["id"] == c2.json()["id"]


async def test_concurrent_acknowledge_only_one_wins(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    inc = await _create(client, team)
    eng = team["eng"]
    assert isinstance(eng, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['id']}"
    results = await asyncio.gather(
        *[client.post(f"{base}/acknowledge", headers=eng.h) for _ in range(4)]
    )
    assert sorted(r.status_code for r in results) == [200, 409, 409, 409]


async def test_comments_are_idempotent_by_client_id(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    inc = await _create(client, team)
    eng = team["eng"]
    assert isinstance(eng, Account)
    base = f"/orgs/{team['org']}/incidents/{inc['id']}"
    cid = str(uuid.uuid4())
    a = await client.post(
        f"{base}/comments", json={"body": "Looking into it", "client_id": cid}, headers=eng.h
    )
    b = await client.post(
        f"{base}/comments", json={"body": "Looking into it", "client_id": cid}, headers=eng.h
    )
    assert (a.status_code, b.status_code) == (201, 200)
    assert a.json()["id"] == b.json()["id"]
    assert a.json()["author"]["display_name"] == "Eli Engineer"
    comments = (await client.get(f"{base}/comments", headers=eng.h)).json()["items"]
    assert len(comments) == 1
    types = [
        e["type"] for e in (await client.get(f"{base}/timeline", headers=eng.h)).json()["items"]
    ]
    assert types.count("comment_added") == 1

    other = await _create(client, team, title="Another one")
    clash = await client.post(
        f"/orgs/{team['org']}/incidents/{other['id']}/comments",
        json={"body": "x", "client_id": cid},
        headers=eng.h,
    )
    assert clash.status_code == 409


async def test_list_filters_and_pagination(
    client: httpx.AsyncClient, team: dict[str, object]
) -> None:
    eng = team["eng"]
    assert isinstance(eng, Account)
    created = [await _create(client, team, title=f"Incident {i}") for i in range(5)]
    await client.post(
        f"/orgs/{team['org']}/incidents/{created[0]['id']}/acknowledge", headers=eng.h
    )
    url = f"/orgs/{team['org']}/incidents"

    keys, cursor = [], None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        page = (await client.get(url, params=params, headers=eng.h)).json()
        keys += [i["key"] for i in page["items"]]
        cursor = page["next_cursor"]
        if not cursor:
            break
    assert keys == [c["key"] for c in reversed(created)]  # newest first, no gaps/dupes

    triggered = (await client.get(url, params={"status": "triggered"}, headers=eng.h)).json()[
        "items"
    ]
    assert len(triggered) == 4
    mine = (await client.get(url, params={"assignee": "me"}, headers=eng.h)).json()["items"]
    assert [i["id"] for i in mine] == [created[0]["id"]]
    by_key = (await client.get(url, params={"q": created[2]["key"]}, headers=eng.h)).json()["items"]
    assert [i["id"] for i in by_key] == [created[2]["id"]]

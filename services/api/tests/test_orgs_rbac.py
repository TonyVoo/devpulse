import httpx
import pytest

from tests.helpers import Account, add_member, create_org, problem, register


@pytest.fixture
async def team(client: httpx.AsyncClient) -> dict[str, object]:
    owner = await register(client, "owner@acme.dev", "Owner")
    admin = await register(client, "admin@acme.dev", "Admin")
    eng = await register(client, "eng@acme.dev", "Eng")
    viewer = await register(client, "viewer@acme.dev", "Viewer")
    org = await create_org(client, owner)
    await add_member(client, org, owner, admin, "admin")
    await add_member(client, org, admin, eng, "engineer")
    await add_member(client, org, admin, viewer, "viewer")
    return {"org": org, "owner": owner, "admin": admin, "eng": eng, "viewer": viewer}


async def test_creator_becomes_owner(client: httpx.AsyncClient) -> None:
    owner = await register(client, "o@x.dev")
    r = await client.post("/orgs", json={"name": "Night Owls"}, headers=owner.h)
    assert r.status_code == 201
    assert r.json()["role"] == "owner"
    assert r.json()["slug"] == "night-owls"
    me = (await client.get("/me", headers=owner.h)).json()
    assert me["memberships"][0]["role"] == "owner"


async def test_slug_conflicts(client: httpx.AsyncClient) -> None:
    a = await register(client, "a@x.dev")
    assert (
        await client.post("/orgs", json={"name": "Alpha", "slug": "taken"}, headers=a.h)
    ).status_code == 201
    r = await client.post("/orgs", json={"name": "Bravo", "slug": "taken"}, headers=a.h)
    assert r.status_code == 409
    assert problem(r)["code"] == "org.slug_taken"
    # Auto-generated slugs get a suffix instead of failing.
    r = await client.post("/orgs", json={"name": "Taken"}, headers=a.h)
    assert r.status_code == 201
    assert r.json()["slug"].startswith("taken-")


@pytest.mark.parametrize(
    ("who", "method", "path", "body", "expected"),
    [
        ("viewer", "GET", "", None, 200),
        ("viewer", "PATCH", "", {"name": "Hacked"}, 403),
        ("eng", "PATCH", "", {"name": "Hacked"}, 403),
        ("admin", "PATCH", "", {"name": "Renamed"}, 200),
        ("admin", "DELETE", "", None, 403),
        ("viewer", "GET", "/members", None, 200),
        ("viewer", "GET", "/invitations", None, 403),
        ("eng", "POST", "/invitations", {"email": "n@x.dev", "role": "viewer"}, 403),
        ("admin", "POST", "/invitations", {"email": "n@x.dev", "role": "engineer"}, 201),
        ("admin", "POST", "/invitations", {"email": "n2@x.dev", "role": "owner"}, 403),
        ("viewer", "GET", "/audit-logs", None, 403),
        ("eng", "GET", "/audit-logs", None, 403),
        ("admin", "GET", "/audit-logs", None, 200),
    ],
)
async def test_rbac_matrix(
    client: httpx.AsyncClient,
    team: dict[str, object],
    who: str,
    method: str,
    path: str,
    body: dict[str, str] | None,
    expected: int,
) -> None:
    acct = team[who]
    assert isinstance(acct, Account)
    r = await client.request(method, f"/orgs/{team['org']}{path}", json=body, headers=acct.h)
    assert r.status_code == expected, r.text
    if expected == 403:
        assert problem(r)["code"].startswith(("rbac.", "member."))


async def test_admin_cannot_change_owner_or_promote_to_owner(
    client: httpx.AsyncClient, team: dict[str, Account]
) -> None:
    org, admin, owner, eng = team["org"], team["admin"], team["owner"], team["eng"]
    r = await client.patch(
        f"/orgs/{org}/members/{owner.id}", json={"role": "viewer"}, headers=admin.h
    )
    assert r.status_code == 403
    r = await client.patch(f"/orgs/{org}/members/{eng.id}", json={"role": "owner"}, headers=admin.h)
    assert r.status_code == 403
    r = await client.patch(
        f"/orgs/{org}/members/{eng.id}", json={"role": "viewer"}, headers=admin.h
    )
    assert r.status_code == 200
    assert r.json()["role"] == "viewer"


async def test_last_owner_is_protected(client: httpx.AsyncClient, team: dict[str, Account]) -> None:
    org, owner, admin = team["org"], team["owner"], team["admin"]
    r = await client.patch(
        f"/orgs/{org}/members/{owner.id}", json={"role": "admin"}, headers=owner.h
    )
    assert r.status_code == 409
    assert problem(r)["code"] == "member.last_owner"
    r = await client.delete(f"/orgs/{org}/members/{owner.id}", headers=owner.h)
    assert r.status_code == 409

    # Transfer ownership, then the original owner may step down / leave.
    r = await client.patch(
        f"/orgs/{org}/members/{admin.id}", json={"role": "owner"}, headers=owner.h
    )
    assert r.status_code == 200
    r = await client.delete(f"/orgs/{org}/members/{owner.id}", headers=owner.h)
    assert r.status_code == 204
    assert (await client.get(f"/orgs/{org}", headers=owner.h)).status_code == 404


async def test_member_can_leave_but_not_remove_others(
    client: httpx.AsyncClient, team: dict[str, Account]
) -> None:
    org, eng, viewer = team["org"], team["eng"], team["viewer"]
    r = await client.delete(f"/orgs/{org}/members/{eng.id}", headers=viewer.h)
    assert r.status_code == 403
    r = await client.delete(f"/orgs/{org}/members/{viewer.id}", headers=viewer.h)
    assert r.status_code == 204


async def test_invitation_rules(client: httpx.AsyncClient, team: dict[str, Account]) -> None:
    org, admin, eng = team["org"], team["admin"], team["eng"]
    stranger = await register(client, "stranger@x.dev")
    intended = await register(client, "intended@x.dev")

    r = await client.post(f"/orgs/{org}/invitations", json={"email": eng.email}, headers=admin.h)
    assert r.status_code == 409  # already a member

    r = await client.post(
        f"/orgs/{org}/invitations", json={"email": intended.email}, headers=admin.h
    )
    token = r.json()["token"]
    dup = await client.post(
        f"/orgs/{org}/invitations", json={"email": intended.email}, headers=admin.h
    )
    assert dup.status_code == 409

    # Someone else holding the token cannot use it.
    r = await client.post(f"/invitations/{token}/accept", headers=stranger.h)
    assert r.status_code == 404
    assert problem(r)["code"] == "invitation.invalid"

    r = await client.post(f"/invitations/{token}/accept", headers=intended.h)
    assert r.status_code == 200
    assert r.json()["org"]["role"] == "engineer"
    # Single use.
    assert (
        await client.post(f"/invitations/{token}/accept", headers=intended.h)
    ).status_code == 404


async def test_revoked_invitation_cannot_be_accepted(
    client: httpx.AsyncClient, team: dict[str, Account]
) -> None:
    org, admin = team["org"], team["admin"]
    invitee = await register(client, "later@x.dev")
    inv = (
        await client.post(
            f"/orgs/{org}/invitations", json={"email": invitee.email}, headers=admin.h
        )
    ).json()
    assert (
        await client.delete(f"/orgs/{org}/invitations/{inv['id']}", headers=admin.h)
    ).status_code == 204
    assert (
        await client.post(f"/invitations/{inv['token']}/accept", headers=invitee.h)
    ).status_code == 404


async def test_audit_log_records_changes(
    client: httpx.AsyncClient, team: dict[str, Account]
) -> None:
    org, owner, eng = team["org"], team["owner"], team["eng"]
    await client.patch(f"/orgs/{org}/members/{eng.id}", json={"role": "admin"}, headers=owner.h)
    r = await client.get(f"/orgs/{org}/audit-logs", params={"limit": 2}, headers=owner.h)
    assert r.status_code == 200
    page = r.json()
    assert page["items"][0]["action"] == "member.role_changed"
    assert page["items"][0]["before"] == {"role": "engineer"}
    assert page["items"][0]["after"] == {"role": "admin"}
    assert page["next_cursor"]

    actions = []
    cursor = None
    while True:
        params = {"limit": 2, **({"cursor": cursor} if cursor else {})}
        body = (await client.get(f"/orgs/{org}/audit-logs", params=params, headers=owner.h)).json()
        actions += [i["action"] for i in body["items"]]
        cursor = body["next_cursor"]
        if not cursor:
            break
    assert actions[-1] == "org.created"
    assert actions.count("member.joined") == 3
    assert len(actions) == len(set(zip(actions, range(len(actions)), strict=True)))


async def test_invalid_cursor_is_422(client: httpx.AsyncClient, team: dict[str, Account]) -> None:
    r = await client.get(
        f"/orgs/{team['org']}/audit-logs", params={"cursor": "%%%"}, headers=team["owner"].h
    )
    assert r.status_code == 422
    assert problem(r)["code"] == "pagination.invalid_cursor"


async def test_deleted_org_is_gone(client: httpx.AsyncClient, team: dict[str, Account]) -> None:
    org, owner = team["org"], team["owner"]
    assert (await client.delete(f"/orgs/{org}", headers=owner.h)).status_code == 204
    assert (await client.get(f"/orgs/{org}", headers=owner.h)).status_code == 404
    assert (await client.get("/orgs", headers=owner.h)).json() == []

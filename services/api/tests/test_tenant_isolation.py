"""Cross-tenant isolation, generated from the route table.

Every route containing `{org_id}` is called by a user who belongs to a *different* org.
The answer must be 404 `org.not_found` — never 2xx, 403 (existence leak) or 422.
New org-scoped routes are covered automatically.
"""

import re
import uuid

import httpx

from tests.helpers import create_org, problem, register

HTTP_METHODS = {"get", "post", "put", "patch", "delete"}


def _org_routes(app) -> list[tuple[str, str]]:  # type: ignore[no-untyped-def]
    # Built from the OpenAPI schema (public, version-stable) rather than router internals.
    return [
        (method.upper(), path)
        for path, ops in app.openapi()["paths"].items()
        if "{org_id}" in path
        for method in ops
        if method in HTTP_METHODS
    ]


async def test_org_routes_exist(app) -> None:  # type: ignore[no-untyped-def]
    assert len(_org_routes(app)) >= 10  # guard against the generator silently finding nothing


async def test_every_org_route_rejects_non_members(app, client: httpx.AsyncClient) -> None:  # type: ignore[no-untyped-def]
    alice = await register(client, "alice@a.dev")
    mallory = await register(client, "mallory@m.dev")
    org_a = await create_org(client, alice, "Alpha")
    await create_org(client, mallory, "Mallory Inc")  # mallory is owner elsewhere

    failures = []
    for method, path in _org_routes(app):
        url = path.replace("/api/v1", "", 1).replace("{org_id}", org_a)
        url = re.sub(r"\{[^}]+\}", str(uuid.uuid4()), url)
        r = await client.request(method, url, json={}, headers=mallory.h)
        if r.status_code != 404 or problem(r).get("code") != "org.not_found":
            failures.append(f"{method} {path} -> {r.status_code} {r.text[:120]}")
    assert not failures, "Tenant isolation violations:\n" + "\n".join(failures)


async def test_unknown_org_is_indistinguishable_from_foreign_org(client: httpx.AsyncClient) -> None:
    alice = await register(client, "alice2@a.dev")
    mallory = await register(client, "mallory2@m.dev")
    org_a = await create_org(client, alice, "Alpha2")
    foreign = await client.get(f"/orgs/{org_a}", headers=mallory.h)
    missing = await client.get(f"/orgs/{uuid.uuid4()}", headers=mallory.h)
    assert foreign.status_code == missing.status_code == 404
    assert problem(foreign)["code"] == problem(missing)["code"]


async def test_org_list_only_shows_own_orgs(client: httpx.AsyncClient) -> None:
    alice = await register(client, "alice3@a.dev")
    bob = await register(client, "bob3@b.dev")
    await create_org(client, alice, "Alpha3")
    await create_org(client, bob, "Bravo3")
    names = [o["name"] for o in (await client.get("/orgs", headers=bob.h)).json()]
    assert names == ["Bravo3"]

from dataclasses import dataclass
from typing import Any

import httpx

PASSWORD = "correct-horse-battery"


@dataclass
class Account:
    id: str
    email: str
    access: str
    refresh: str
    session_id: str

    @property
    def h(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.access}"}


async def register(client: httpx.AsyncClient, email: str, name: str = "Test User") -> Account:
    r = await client.post(
        "/auth/register", json={"email": email, "password": PASSWORD, "display_name": name}
    )
    assert r.status_code == 201, r.text
    body = r.json()
    return Account(
        id=body["user"]["id"],
        email=email,
        access=body["access_token"],
        refresh=body["refresh_token"],
        session_id=body["session_id"],
    )


async def create_org(client: httpx.AsyncClient, owner: Account, name: str = "Acme") -> str:
    r = await client.post("/orgs", json={"name": name}, headers=owner.h)
    assert r.status_code == 201, r.text
    return str(r.json()["id"])


async def add_member(
    client: httpx.AsyncClient, org_id: str, inviter: Account, invitee: Account, role: str
) -> None:
    r = await client.post(
        f"/orgs/{org_id}/invitations",
        json={"email": invitee.email, "role": role},
        headers=inviter.h,
    )
    assert r.status_code == 201, r.text
    r = await client.post(f"/invitations/{r.json()['token']}/accept", headers=invitee.h)
    assert r.status_code == 200, r.text


def problem(r: httpx.Response) -> dict[str, Any]:
    assert r.headers["content-type"].startswith("application/problem+json"), r.text
    body: dict[str, Any] = r.json()
    return body


# ----------------------------------------------------------------------------- phase 2


async def create_service(
    client: httpx.AsyncClient, org_id: str, owner: Account, name: str = "Checkout API", **extra: Any
) -> dict[str, Any]:
    r = await client.post(f"/orgs/{org_id}/services", json={"name": name, **extra}, headers=owner.h)
    assert r.status_code == 201, r.text
    body: dict[str, Any] = r.json()
    return body


async def create_ingest_key(
    client: httpx.AsyncClient, org_id: str, owner: Account, **extra: Any
) -> str:
    r = await client.post(
        f"/orgs/{org_id}/ingest-keys", json={"name": "ci", **extra}, headers=owner.h
    )
    assert r.status_code == 201, r.text
    return str(r.json()["key"])


def ingest_h(key: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {key}"}


async def ingest_points(
    client: httpx.AsyncClient, key: str, service: str, points: list[dict[str, Any]]
) -> httpx.Response:
    return await client.post(
        "http://test/ingest/v1/metrics",
        json={"service": service, "points": points},
        headers=ingest_h(key),
    )

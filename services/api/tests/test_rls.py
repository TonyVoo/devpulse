"""Row-level security (ADR-026): the database itself separates tenants once a request has
set its organization, even for a query that forgets `WHERE org_id = …`."""

from uuid import UUID

import asyncpg
import httpx
import pytest

from tests.helpers import create_org, create_service, register


async def _two_orgs(client: httpx.AsyncClient) -> tuple[str, str]:
    a = await register(client, "rls-a@example.com")
    b = await register(client, "rls-b@example.com")
    org_a, org_b = await create_org(client, a, "Org A"), await create_org(client, b, "Org B")
    await create_service(client, org_a, a, "alpha")
    await create_service(client, org_b, b, "bravo")
    return org_a, org_b


async def test_suite_runs_as_a_role_subject_to_rls(db_dsn: str) -> None:
    conn = await asyncpg.connect(db_dsn)
    try:
        assert await conn.fetchval(
            "SELECT NOT (rolsuper OR rolbypassrls) FROM pg_roles WHERE rolname = current_user"
        )
        forced = await conn.fetchval(
            "SELECT count(*) FROM pg_class WHERE relname IN ('incidents', 'services', 'organizations') "
            "AND relrowsecurity AND relforcerowsecurity"
        )
        assert forced == 3
    finally:
        await conn.close()


async def test_policies_hide_and_block_other_orgs(client: httpx.AsyncClient, db_dsn: str) -> None:
    org_a, org_b = await _two_orgs(client)
    conn = await asyncpg.connect(db_dsn)
    try:
        # No org set (workers, auth): everything visible, as before.
        assert await conn.fetchval("SELECT count(*) FROM services") == 2

        async with conn.transaction():
            await conn.execute("SELECT set_config('app.org_id', $1, true)", org_a)
            # A query that "forgot" its org filter still only sees org A.
            names = [r["name"] for r in await conn.fetch("SELECT name FROM services")]
            assert names == ["alpha"]
            assert await conn.fetchval("SELECT count(*) FROM organizations") == 1
            assert await conn.fetchval("SELECT count(*) FROM memberships") == 1
            # Writing into another org is rejected by the policy's WITH CHECK.
            with pytest.raises(asyncpg.InsufficientPrivilegeError):
                await conn.execute(
                    "UPDATE services SET name = 'pwned' WHERE org_id = $1", UUID(org_b)
                )  # matches nothing visible → 0 rows; now try an explicit cross-org insert:
                await conn.execute(
                    "INSERT INTO services (id, org_id, slug, name, environment, tier, health, tags) "
                    "VALUES (gen_random_uuid(), $1, 'x', 'x', 'production', 'low', 'unknown', '{}')",
                    UUID(org_b),
                )

        # The setting was transaction-local: it doesn't stick to the pooled connection.
        assert await conn.fetchval("SELECT count(*) FROM services") == 2
        assert (
            await conn.fetchval("SELECT name FROM services WHERE org_id = $1", UUID(org_b))
            == "bravo"
        )
    finally:
        await conn.close()


async def test_org_scoped_requests_run_with_the_org_set(client: httpx.AsyncClient) -> None:
    """The API's own requests go through the policies (the suite connects as a non-superuser
    role), and nothing in the request path needs rows from another org."""
    a = await register(client, "rls-c@example.com")
    org = await create_org(client, a, "Org C")
    await create_service(client, org, a, "charlie")
    r = await client.get(f"/orgs/{org}/services", headers=a.h)
    assert [s["slug"] for s in r.json()["items"]] == ["charlie"]

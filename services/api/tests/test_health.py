import httpx


async def test_healthz_and_readyz(app) -> None:  # type: ignore[no-untyped-def]
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        assert (await c.get("/healthz")).json() == {"status": "ok", "release": "dev"}
        r = await c.get("/readyz")
        assert r.status_code == 200, r.text
        assert r.json()["checks"] == {"database": "ok", "migrations": "ok", "redis": "ok"}

"""Ingestion + read-path load test against a running DevPulse API (docs/LOAD_TEST.md).

    python -m app.scripts.loadtest --api http://localhost:8000 [--seconds 30] [--out report.json]

Creates a throwaway account and org (synthetic data, flagged demo where the API allows),
then runs, in order:
  1. ingestion steps at increasing concurrency (each worker has its own ingest key and
     posts batches of metric points for distinct services),
  2. the main read endpoints while a moderate ingestion load continues,
  3. a rollup-lag check (are 1-minute rollups keeping up with what was ingested?).
Prints a summary and writes the raw numbers as JSON. Never run it against production.
"""

import argparse
import asyncio
import json
import secrets
import statistics
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import httpx

POINTS_PER_BATCH = 500
METRICS = (
    "http.server.duration_ms",
    "http.server.requests",
    "http.server.errors",
    "process.cpu.utilization",
    "db.pool.connections_in_use",
)


@dataclass
class Stat:
    latencies_ms: list[float] = field(default_factory=list)
    errors: dict[str, int] = field(default_factory=dict)
    units: int = 0  # points or requests

    def add(self, ms: float, status: int, ok: bool, units: int = 1) -> None:
        if ok:
            self.latencies_ms.append(ms)
            self.units += units
        else:
            self.errors[str(status)] = self.errors.get(str(status), 0) + 1

    def summary(self, seconds: float) -> dict[str, Any]:
        lat = sorted(self.latencies_ms)

        def pct(p: float) -> float | None:
            if not lat:
                return None
            return round(lat[min(len(lat) - 1, int(len(lat) * p))], 1)

        return {
            "ok": len(lat),
            "errors": self.errors,
            "per_second": round(len(lat) / seconds, 1),
            "units_per_second": round(self.units / seconds, 1),
            "p50_ms": pct(0.50),
            "p95_ms": pct(0.95),
            "p99_ms": pct(0.99),
            "mean_ms": round(statistics.fmean(lat), 1) if lat else None,
        }


async def _setup(client: httpx.AsyncClient, workers: int) -> dict[str, Any]:
    email = f"loadtest-{int(time.time())}-{secrets.token_hex(3)}@example.com"
    password = secrets.token_urlsafe(18)  # throwaway account, never printed
    r = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "display_name": "Load Test"},
    )
    r.raise_for_status()
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    org = (await client.post("/api/v1/orgs", json={"name": "Load test org"}, headers=h)).json()[
        "id"
    ]
    services = []
    for i in range(20):
        s = await client.post(
            f"/api/v1/orgs/{org}/services", json={"name": f"svc-{i:02d}"}, headers=h
        )
        services.append(s.json())
    keys = []
    for i in range(workers):
        k = await client.post(
            f"/api/v1/orgs/{org}/ingest-keys", json={"name": f"lt-{i}"}, headers=h
        )
        keys.append(k.json()["key"])
    return {"headers": h, "org": org, "services": services, "keys": keys, "email": email}


def _batch(service: str) -> dict[str, Any]:
    now = datetime.now(UTC)
    points = [
        {
            "name": METRICS[i % len(METRICS)],
            "ts": (now - timedelta(milliseconds=i * 20)).isoformat(),
            "value": float(100 + (i % 37)),
            "labels": {"route": f"/r{i % 8}"},
        }
        for i in range(POINTS_PER_BATCH)
    ]
    return {"service": service, "points": points}


async def _ingest_worker(
    client: httpx.AsyncClient, key: str, service: str, until: float, stat: Stat
) -> None:
    h = {"Authorization": f"Bearer {key}"}
    while time.monotonic() < until:
        body = _batch(service)
        t0 = time.perf_counter()
        try:
            r = await client.post("/ingest/v1/metrics", json=body, headers=h)
            stat.add(
                (time.perf_counter() - t0) * 1000,
                r.status_code,
                r.status_code == 202,
                POINTS_PER_BATCH,
            )
        except httpx.HTTPError as e:
            stat.add(0, 0, False)
            stat.errors[type(e).__name__] = stat.errors.get(type(e).__name__, 0) + 1


async def ingest_step(
    client: httpx.AsyncClient, env: dict[str, Any], workers: int, seconds: float
) -> dict[str, Any]:
    stat = Stat()
    until = time.monotonic() + seconds
    await asyncio.gather(
        *(
            _ingest_worker(client, env["keys"][i], env["services"][i % 20]["slug"], until, stat)
            for i in range(workers)
        )
    )
    out = stat.summary(seconds)
    out["workers"] = workers
    out["points_per_batch"] = POINTS_PER_BATCH
    return out


async def read_step(
    client: httpx.AsyncClient, env: dict[str, Any], seconds: float
) -> dict[str, Any]:
    org, h = env["org"], env["headers"]
    svc = env["services"][0]["id"]
    end = datetime.now(UTC)
    endpoints = {
        "overview": f"/api/v1/orgs/{org}/overview?window=24h",
        "services_list": f"/api/v1/orgs/{org}/services?limit=50",
        "incidents_list": f"/api/v1/orgs/{org}/incidents?limit=50",
        "metrics_6h": f"/api/v1/orgs/{org}/services/{svc}/metrics?names=http.server.duration_ms:p95"
        f"&names=http.server.error_rate&from={(end - timedelta(hours=6)).isoformat()}"
        f"&to={end.isoformat()}",
        "sync_incidents": f"/api/v1/orgs/{org}/sync/incidents?cursor=0",
    }
    stats = {name: Stat() for name in endpoints}
    until = time.monotonic() + seconds

    async def reader(name: str, url: str) -> None:
        while time.monotonic() < until:
            t0 = time.perf_counter()
            r = await client.get(url.replace("+00:00", "Z"), headers=h)
            stats[name].add((time.perf_counter() - t0) * 1000, r.status_code, r.status_code == 200)

    background = asyncio.create_task(ingest_step(client, env, 4, seconds))
    await asyncio.gather(*(reader(n, u) for n, u in endpoints.items() for _ in range(2)))
    ingest = await background
    result = {name: s.summary(seconds) for name, s in stats.items()}
    result["_concurrent_ingest"] = ingest
    return result


async def rollup_lag(client: httpx.AsyncClient, env: dict[str, Any]) -> dict[str, Any]:
    """Seconds until the last ingested minute shows up in the 1-minute rollups."""
    org, h, svc = env["org"], env["headers"], env["services"][0]["id"]
    t0 = time.monotonic()
    target = datetime.now(UTC).replace(second=0, microsecond=0) - timedelta(minutes=1)
    while time.monotonic() - t0 < 120:
        end = datetime.now(UTC)
        r = await client.get(
            f"/api/v1/orgs/{org}/services/{svc}/metrics",
            params={
                "names": "http.server.requests:count",
                "from": (end - timedelta(minutes=10)).isoformat(),
                "to": end.isoformat(),
                "step": 60,
            },
            headers=h,
        )
        pts = [p for p in r.json()["series"][0]["points"] if p[1] is not None]
        if pts and datetime.fromisoformat(pts[-1][0]) >= target:
            return {"caught_up_after_s": round(time.monotonic() - t0, 1)}
        await asyncio.sleep(2)
    return {"caught_up_after_s": None, "note": "rollups did not catch up within 120 s"}


async def main(api: str, seconds: float, steps: list[int]) -> dict[str, Any]:
    limits = httpx.Limits(max_connections=200, max_keepalive_connections=200)
    async with httpx.AsyncClient(base_url=api, timeout=30, limits=limits) as client:
        env = await _setup(client, max(steps))
        report: dict[str, Any] = {
            "api": api,
            "started_at": datetime.now(UTC).isoformat(),
            "seconds_per_step": seconds,
            "ingest": [],
        }
        for w in steps:
            step = await ingest_step(client, env, w, seconds)
            report["ingest"].append(step)
            print(
                f"ingest workers={w:>3}  {step['units_per_second']:>9,.0f} points/s  "
                f"p50={step['p50_ms']} ms  p95={step['p95_ms']} ms  p99={step['p99_ms']} ms  "
                f"errors={step['errors']}"
            )
        report["reads"] = await read_step(client, env, seconds)
        for name, s in report["reads"].items():
            if not name.startswith("_"):
                print(
                    f"read {name:<15} {s['per_second']:>7} req/s  p50={s['p50_ms']} ms  p95={s['p95_ms']} ms  errors={s['errors']}"
                )
        report["rollup"] = await rollup_lag(client, env)
        print(f"rollup lag: {report['rollup']}")
        report["org_id"] = env["org"]
    return report


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--api", default="http://localhost:8000")
    p.add_argument("--seconds", type=float, default=20)
    p.add_argument("--steps", default="1,4,8,16")
    p.add_argument("--out", default=None)
    a = p.parse_args()
    if not a.api.startswith(("http://localhost", "http://127.0.0.1", "http://api:")):
        raise SystemExit("Refusing to load-test a non-local API without editing this guard.")
    result = asyncio.run(main(a.api, a.seconds, [int(x) for x in a.steps.split(",")]))
    if a.out:
        Path(a.out).write_text(json.dumps(result, indent=2))

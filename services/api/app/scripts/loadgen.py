"""Synthetic load generator: sends telemetry and deployments through the REAL ingest API.

    python -m app.scripts.loadgen --key dp_ingest_... [--api http://localhost:8000]
                                  [--incident-after 120] [--duration 900]

Every 10 s it posts request counts, errors, latency samples, CPU/memory and the odd log
line for each demo service. With --incident-after N it simulates a bad release of
checkout-api N seconds in: a deployment event, then elevated latency and errors that the
seeded alert rules detect — exercising ingestion → rollups → alerting → incidents →
deployment correlation end to end. Stdlib only (runs inside the API image).
"""

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime
from typing import Any

SERVICES = {
    # slug: (requests per 10 s, base latency ms, base error ratio)
    "checkout-api": (600, 140, 0.004),
    "payments": (300, 220, 0.002),
    "search": (900, 60, 0.01),
    "notifications": (150, 35, 0.001),
}
TICK_S = 10


def post(api: str, key: str, path: str, body: dict[str, Any]) -> int:
    if not api.startswith(("http://", "https://")):
        raise SystemExit("--api must be an http(s) URL")
    req = urllib.request.Request(
        f"{api.rstrip('/')}{path}",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return int(resp.status)
    except urllib.error.HTTPError as e:
        print(f"  {path} → {e.code}: {e.read()[:200]!r}", file=sys.stderr)
        return e.code
    except urllib.error.URLError as e:
        print(f"  {path} → unreachable: {e.reason}", file=sys.stderr)
        return 0


def tick(api: str, key: str, now: datetime, incident: bool, rng: random.Random) -> None:
    ts = now.isoformat()
    for slug, (rpm, latency, err) in SERVICES.items():
        bad = incident and slug == "checkout-api"
        requests = max(1, int(rng.gauss(rpm, rpm * 0.08)))
        error_ratio = 0.12 if bad else err
        errors = sum(1 for _ in range(requests) if rng.random() < error_ratio)
        base = latency * (7.5 if bad else 1.0)
        samples = [max(1.0, rng.lognormvariate(0, 0.35) * base) for _ in range(40)]
        points = [
            {"name": "http.server.requests", "ts": ts, "value": requests},
            {"name": "http.server.errors", "ts": ts, "value": errors},
            {
                "name": "process.cpu.utilization",
                "ts": ts,
                "value": round(min(0.98, rng.gauss(0.85 if bad else 0.35, 0.05)), 3),
            },
            {"name": "process.memory.usage_bytes", "ts": ts, "value": int(rng.gauss(520e6, 15e6))},
            {
                "name": "db.pool.connections_in_use",
                "ts": ts,
                "value": 50 if bad else int(rng.gauss(14, 3)),
            },
            *({"name": "http.server.duration_ms", "ts": ts, "value": round(v, 1)} for v in samples),
        ]
        post(api, key, "/ingest/v1/metrics", {"service": slug, "points": points})
        if bad or rng.random() < 0.15:
            post(
                api,
                key,
                "/ingest/v1/logs",
                {
                    "service": slug,
                    "logs": [
                        {
                            "ts": ts,
                            "level": "error" if bad else "info",
                            "message": (
                                f"Timeout acquiring DB connection after {rng.randint(3000, 5000)}ms (pool exhausted)"
                                if bad
                                else f"Handled {requests} requests"
                            ),
                        }
                    ],
                },
            )


def main() -> None:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--key", required=True, help="demo ingest key from seed_demo")
    p.add_argument("--api", default="http://localhost:8000")
    p.add_argument("--incident-after", type=int, default=None, help="seconds until a bad release")
    p.add_argument("--duration", type=int, default=0, help="stop after N seconds (0 = forever)")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args()

    rng = random.Random(args.seed)
    started = time.monotonic()
    deployed = False
    print(f"Sending demo telemetry to {args.api} every {TICK_S}s (Ctrl-C to stop)")
    while True:
        elapsed = time.monotonic() - started
        incident = args.incident_after is not None and elapsed >= args.incident_after
        if incident and not deployed:
            version = f"v2.{rng.randint(10, 99)}.0"
            post(
                args.api,
                args.key,
                "/ingest/v1/deployments",
                {
                    "service": "checkout-api",
                    "version": version,
                    "external_id": f"loadgen-{int(time.time())}",
                    "status": "succeeded",
                    "commit_sha": f"{rng.getrandbits(40):010x}",
                    "commit_author": "demo-bot",
                    "commit_message": "Increase DB query concurrency (demo bad release)",
                    "started_at": datetime.now(UTC).isoformat(),
                },
            )
            print(
                f"[{int(elapsed)}s] deployed checkout-api {version} — injecting latency and errors"
            )
            deployed = True
        tick(args.api, args.key, datetime.now(UTC), incident, rng)
        if args.duration and elapsed >= args.duration:
            return
        time.sleep(TICK_S)


if __name__ == "__main__":
    main()

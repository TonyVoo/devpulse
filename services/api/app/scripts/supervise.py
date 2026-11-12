"""All-in-one process for small deployments (Render free tier: one web service, no workers).

    python -m app.scripts.supervise

1. applies database migrations (fails fast),
2. starts the API (uvicorn), one Celery process with the beat scheduler embedded
   (`--pool solo -B`: rollups, alert evaluation, AI investigations, cleanup) and the
   outbox relay (realtime + push),
3. forwards SIGTERM/SIGINT to all of them, and exits as soon as any one stops, so the
   platform restarts the whole service instead of running half of it.

Larger deployments run these as separate services (infra/compose, docs/DEPLOYMENT.md).
"""

import os
import signal
import subprocess
import sys
import time
from types import FrameType

GRACE_S = 25  # Render waits 30 s by default before killing the container


def _commands() -> dict[str, list[str]]:
    port = os.environ.get("PORT", "8000")
    workers = os.environ.get("WEB_CONCURRENCY", "1")
    forwarded = os.environ.get("FORWARDED_ALLOW_IPS", "127.0.0.1")
    return {
        "api": [
            "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", port,  # noqa: S104 - in a container
            "--workers", workers, "--proxy-headers", "--forwarded-allow-ips", forwarded,
        ],
        "worker": [
            "celery", "-A", "app.workers.celery_app:celery", "worker", "-B",
            "--pool", "solo", "--loglevel", "INFO",
            "--schedule", "/tmp/celerybeat-schedule",  # noqa: S108 - container-private /tmp
        ],
        "relay": [sys.executable, "-m", "app.workers.relay"],
    }  # fmt: skip


def main() -> int:
    print("supervise: applying migrations", flush=True)
    if subprocess.call(["alembic", "upgrade", "head"]) != 0:  # noqa: S607 - fixed command
        print("supervise: migrations failed", file=sys.stderr, flush=True)
        return 1

    children = {name: subprocess.Popen(cmd) for name, cmd in _commands().items()}  # noqa: S603
    stopping = False

    def stop(signum: int, _frame: FrameType | None) -> None:
        nonlocal stopping
        stopping = True
        for proc in children.values():
            if proc.poll() is None:
                proc.send_signal(signum)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    exited: str | None = None
    while exited is None:
        time.sleep(0.5)
        exited = next((n for n, p in children.items() if p.poll() is not None), None)
    if not stopping:
        print(f"supervise: {exited} exited ({children[exited].returncode}); stopping", flush=True)
        stop(signal.SIGTERM, None)
    deadline = time.monotonic() + GRACE_S
    for proc in children.values():
        try:
            proc.wait(timeout=max(0.1, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            proc.kill()
    return 0 if stopping else 1


if __name__ == "__main__":
    raise SystemExit(main())

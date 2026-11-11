"""Celery app (worker + beat). Tasks are thin wrappers around async service functions."""

from celery import Celery

from app.core.config import get_settings
from app.core.logging import configure_logging

settings = get_settings()
configure_logging(settings.log_level, json=settings.log_json)

celery = Celery("devpulse", broker=settings.redis_url, backend=None, include=["app.workers.tasks"])
celery.conf.update(
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    worker_prefetch_multiplier=1,
    task_time_limit=300,
    timezone="UTC",
    # App logs are already structured JSON on stdout; don't re-label them as WARNING.
    worker_redirect_stdouts_level="INFO",
    beat_schedule={
        "purge-expired-refresh-tokens": {
            "task": "auth.purge_expired_refresh_tokens",
            "schedule": 3600,
        },
        # Short expiry: if workers fall behind, skip stale runs instead of piling them up.
        "rollup": {"task": "telemetry.rollup", "schedule": 20, "options": {"expires": 18}},
        "evaluate-alerts": {"task": "alerts.evaluate", "schedule": 30, "options": {"expires": 25}},
        "maintain-partitions": {"task": "telemetry.maintain_partitions", "schedule": 3600},
        "cleanup": {"task": "maintenance.cleanup", "schedule": 3600},
    },
)

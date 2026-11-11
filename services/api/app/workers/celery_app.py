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
    beat_schedule={
        "purge-expired-refresh-tokens": {
            "task": "auth.purge_expired_refresh_tokens",
            "schedule": 60 * 60,  # hourly
        },
    },
)

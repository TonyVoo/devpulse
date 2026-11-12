"""Token/cost accounting (AI_ARCHITECTURE.md §7). Every provider call writes one row."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.modules.ai.models import AIUsage
from app.modules.ai.providers.base import Usage


def cost_micros(model: str, usage: Usage) -> int:
    """USD per million tokens == micro-dollars per token. Unknown models cost 0 and are
    logged by the caller; the pricing table lives in settings, not code."""
    prices = get_settings().ai_pricing.get(model)
    if prices is None:
        return 0
    p_in, p_out, p_read, p_write = prices
    return round(
        usage.input_tokens * p_in
        + usage.output_tokens * p_out
        + usage.cached_tokens * p_read
        + usage.cache_write_tokens * p_write
    )


def usage_row(
    *,
    org_id: UUID,
    investigation_id: UUID | None,
    purpose: str,
    provider: str,
    model: str,
    usage: Usage,
    latency_ms: int,
    attempt: int,
    outcome: str,
    request_id: str | None,
) -> AIUsage:
    return AIUsage(
        org_id=org_id,
        investigation_id=investigation_id,
        purpose=purpose,
        provider=provider,
        model=model,
        input_tokens=usage.input_tokens,
        output_tokens=usage.output_tokens,
        cached_tokens=usage.cached_tokens,
        cache_write_tokens=usage.cache_write_tokens,
        cost_micros=cost_micros(model, usage),
        latency_ms=latency_ms,
        attempt=attempt,
        outcome=outcome,
        request_id=request_id,
    )


def month_start(now: datetime | None = None) -> datetime:
    now = now or datetime.now(UTC)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def month_to_date_cost(session: AsyncSession, org_id: UUID) -> int:
    total = await session.scalar(
        select(func.coalesce(func.sum(AIUsage.cost_micros), 0)).where(
            AIUsage.org_id == org_id, AIUsage.created_at >= month_start()
        )
    )
    return int(total or 0)

"""Run the golden AI scenarios against a provider and score them (AI_ARCHITECTURE.md §8).

    make ai-eval                      # rule-based demo analyzer (free, deterministic)
    make ai-eval PROVIDER=gemini      # real model: GEMINI_API_KEY (free tier works)
    make ai-eval PROVIDER=anthropic   # real model: makes billed API calls (ANTHROPIC_API_KEY)

Creates a throwaway organization with synthetic `is_demo` data, runs each scenario through
the real pipeline, prints top-1 cause accuracy, citation validity, tokens and cost, then
deletes the organization. Refuses to run in production.
"""

import argparse
import asyncio
import sys
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, func, select

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.ids import uuid7
from app.modules.ai.models import AIInvestigation, AISettings, AIUsage, RunStatus, Trigger
from app.modules.ai.pipeline import run_investigation, start_investigation
from app.modules.ai.scenarios import SCENARIOS
from app.modules.organizations.models import Organization


async def main(provider: str, model: str | None) -> int:
    if get_settings().is_production:
        print("ai-eval refuses to run in production", file=sys.stderr)
        return 2
    sm = get_sessionmaker()
    org_id = uuid7()
    async with sm() as s:
        s.add(
            Organization(id=org_id, slug=f"ai-eval-{org_id.hex[:10]}", name="AI eval (temporary)")
        )
        await s.flush()
        s.add(
            AISettings(
                org_id=org_id,
                enabled=True,
                provider=provider,
                model=model,
                monthly_budget_micros=5_000_000,
                max_tokens_per_run=300_000,
                data_redaction={"emails": True, "ips": True, "secrets": True},
            )
        )
        await s.commit()
    hits, rows = 0, []
    try:
        for sc in SCENARIOS:
            async with sm() as s:
                inc = await sc.build(s, org_id, datetime.now(UTC) - timedelta(minutes=10))
                await s.commit()
                inv = await start_investigation(s, inc, trigger=Trigger.MANUAL, requested_by=None)
                if inv is None:
                    raise RuntimeError("could not start")
                await s.commit()
                inv_id = inv.id
            async with sm() as s:
                await run_investigation(s, inv_id)
            async with sm() as s:
                inv = await s.get(AIInvestigation, inv_id)
                if inv is None:
                    raise RuntimeError("investigation vanished")
                cost = await s.scalar(
                    select(func.coalesce(func.sum(AIUsage.cost_micros), 0)).where(
                        AIUsage.investigation_id == inv_id
                    )
                )
                top = ""
                ok = False
                if inv.status == RunStatus.SUCCEEDED and inv.result:
                    top = inv.result["probable_causes"][0]["cause"]
                    ok = any(k in top.lower() for k in sc.expected_keywords)
                hits += ok
                rows.append(
                    (
                        sc.name,
                        inv.status.value,
                        inv.error_code or "",
                        ok,
                        top,
                        inv.tokens_used,
                        int(cost or 0),
                    )
                )
    finally:
        async with sm() as s:
            await s.execute(delete(Organization).where(Organization.id == org_id))
            await s.commit()

    print(f"provider={provider} model={model or 'default'}")
    for name, status, code, ok, top, tokens, cost in rows:
        mark = "PASS" if ok else "FAIL"
        print(
            f"  {mark} {name:16} {status:9} {code:22} tokens={tokens:<7} ${cost / 1e6:.4f}  {top}"
        )
    total = sum(r[6] for r in rows)
    print(
        f"top-1 cause hit rate: {hits}/{len(rows)} · citations: validated server-side · "
        f"total cost ${total / 1e6:.4f}"
    )
    return 0 if hits == len(rows) else 1


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--provider", default="fake", choices=["fake", "gemini", "anthropic"])
    p.add_argument("--model", default=None)
    a = p.parse_args()
    raise SystemExit(asyncio.run(main(a.provider, a.model)))

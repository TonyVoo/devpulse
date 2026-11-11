"""Create a clearly-labelled demo organization for an EXISTING user.

    python -m app.scripts.seed_demo --owner-email you@example.com

* Refuses to run when APP_ENV=production.
* Everything it creates is flagged `is_demo` (services, the ingest key → all telemetry it
  receives). It inserts NO metrics, incidents or deployments itself: those come from the
  load generator (`app.scripts.loadgen`) through the real ingest API, so every product
  code path is exercised exactly as for real data.
* Idempotent: re-running reuses the org/services/rules and issues a fresh demo key.
"""

import argparse
import asyncio
import sys
from dataclasses import dataclass

from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.deps import RequestMeta
from app.core.tenancy import OrgContext
from app.modules.alerts.models import Aggregation, AlertRule, Comparator, Severity
from app.modules.organizations.models import Membership, Organization
from app.modules.rbac.permissions import ROLE_PERMISSIONS, Role
from app.modules.services.models import Service, Tier
from app.modules.services.schemas import IngestKeyCreateIn
from app.modules.services.service import ServiceCatalog
from app.modules.users.models import User

DEMO_SLUG = "devpulse-demo"
META = RequestMeta(ip=None, user_agent="seed_demo", request_id=None)


@dataclass(frozen=True)
class DemoService:
    slug: str
    name: str
    tier: Tier
    repo: str


SERVICES = [
    DemoService(
        "checkout-api",
        "Checkout API",
        Tier.CRITICAL,
        "https://github.com/devpulse-demo/checkout-api",
    ),
    DemoService("payments", "Payments", Tier.CRITICAL, "https://github.com/devpulse-demo/payments"),
    DemoService("search", "Search", Tier.HIGH, "https://github.com/devpulse-demo/search"),
    DemoService(
        "notifications", "Notifications", Tier.LOW, "https://github.com/devpulse-demo/notifications"
    ),
]


async def seed(owner_email: str) -> str:
    async with get_sessionmaker()() as session:
        user = await session.scalar(select(User).where(User.email == owner_email.strip().lower()))
        if user is None:
            raise SystemExit(f"No user {owner_email!r}. Register in the app first.")

        org = await session.scalar(select(Organization).where(Organization.slug == DEMO_SLUG))
        if org is None:
            org = Organization(slug=DEMO_SLUG, name="DevPulse Demo")
            session.add(org)
            await session.flush()
        member = await session.scalar(
            select(Membership).where(Membership.org_id == org.id, Membership.user_id == user.id)
        )
        if member is None:
            session.add(Membership(org_id=org.id, user_id=user.id, role=Role.OWNER))

        services: dict[str, Service] = {}
        for d in SERVICES:
            svc = await session.scalar(
                select(Service).where(
                    Service.org_id == org.id,
                    Service.slug == d.slug,
                    Service.environment == "production",
                )
            )
            if svc is None:
                svc = Service(
                    org_id=org.id,
                    slug=d.slug,
                    name=d.name,
                    environment="production",
                    tier=d.tier,
                    repo_url=d.repo,
                    owner_team="demo",
                    is_demo=True,
                    description="Demo service fed by the synthetic load generator.",
                )
                session.add(svc)
                await session.flush()
            services[d.slug] = svc

        rules = [
            (
                "Checkout p95 latency > 800 ms",
                "checkout-api",
                "http.server.duration_ms",
                Aggregation.P95,
                800.0,
                Severity.SEV2,
                60,
            ),
            (
                "Checkout error rate > 5%",
                "checkout-api",
                "http.server.error_rate",
                Aggregation.RATIO,
                0.05,
                Severity.SEV1,
                60,
            ),
            (
                "Payments p95 latency > 1200 ms",
                "payments",
                "http.server.duration_ms",
                Aggregation.P95,
                1200.0,
                Severity.SEV2,
                120,
            ),
            (
                "Search error rate > 10%",
                "search",
                "http.server.error_rate",
                Aggregation.RATIO,
                0.10,
                Severity.SEV3,
                120,
            ),
        ]
        for name, slug, metric, agg, threshold, sev, for_s in rules:
            exists = await session.scalar(
                select(AlertRule).where(AlertRule.org_id == org.id, AlertRule.name == name)
            )
            if exists is None:
                session.add(
                    AlertRule(
                        org_id=org.id,
                        service_id=services[slug].id,
                        name=name,
                        metric=metric,
                        aggregation=agg,
                        comparator=Comparator.GT,
                        threshold=threshold,
                        window_s=180,
                        for_s=for_s,
                        severity=sev,
                        created_by=user.id,
                    )
                )
        await session.commit()

        ctx = OrgContext(
            org_id=org.id,
            user_id=user.id,
            role=Role.OWNER,
            permissions=ROLE_PERMISSIONS[Role.OWNER],
        )
        _, raw = await ServiceCatalog(session, ctx).create_key(
            IngestKeyCreateIn(
                name="demo load generator",
                scopes=["metrics:write", "logs:write", "deployments:write"],
            ),
            META,
            is_demo=True,
        )
        return raw


def main() -> None:
    if get_settings().is_production:
        sys.exit("Refusing to seed demo data in production.")
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--owner-email", required=True)
    args = parser.parse_args()
    key = asyncio.run(seed(args.owner_email))
    print("Demo organization 'DevPulse Demo' is ready (all data flagged as demo).")
    print("Demo ingest key (shown once):")
    print(key)


if __name__ == "__main__":
    main()

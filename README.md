# DevPulse

> Your entire engineering infrastructure in your pocket.

DevPulse is an AI-native engineering observability platform. Engineers monitor services,
track deployments, run incidents and get evidence-based AI root-cause analysis — first-class
on mobile, with a web dashboard for administration and deep analysis.

**Status: Phase 4 (AI investigator) — evidence-grounded incident analysis on mobile and web; real-model analysis needs a (free) `GEMINI_API_KEY`, push delivery awaits a Firebase project.**
Exact status per item: [docs/ROADMAP.md §3](docs/ROADMAP.md).

## Components

| Component | Path | Stack | Status |
|---|---|---|---|
| Mobile app (iOS/Android) | `apps/mobile` | Flutter 3.47, Riverpod 3, go_router 18, Dio, Drift, fl_chart | Offline-first: local cache, delta sync, offline actions with replay, realtime updates; AI analysis, approvals and follow-up questions |
| Web dashboard | `apps/web` | Next.js 16 (App Router), TypeScript, Tailwind 4, TanStack Query | Auth, orgs, members, overview, services, ingest keys, incidents with AI analysis, AI settings & usage |
| API (modular monolith) | `services/api` | FastAPI, SQLAlchemy 2.1, Alembic, Pydantic v2, PostgreSQL 16, Redis 7 | Auth, RBAC, telemetry, alerting, incidents, deployments, GitHub, AI investigator |
| Workers | `services/api` (same codebase, `worker` + `relay` entrypoints) | Celery + Redis | Rollups, alert evaluation, partitions, cleanup, AI investigations; outbox relay → realtime + push + auto-investigate |
| Infra / observability | `infra/` | Docker Compose; OTel/Prometheus/Grafana planned | Compose stack; Sentry hook (optional DSN) |
| API contract | `packages/api-contract` | OpenAPI generated from FastAPI → TS types (Dart later) | Generated, drift-checked in CI |

## Documentation

| Doc | Contents |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Repository assessment, monorepo layout, system architecture, module boundaries, tenancy, realtime |
| [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | Entities, ER diagram, indexes, partitioning, retention |
| [API.md](docs/API.md) | REST/WebSocket contract, conventions, error model, sync protocol |
| [MOBILE_ARCHITECTURE.md](docs/MOBILE_ARCHITECTURE.md) | Flutter layering, navigation map, offline-first, sync, realtime, push, deep links |
| [DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | Tokens, typography, components, state designs, accessibility |
| [AI_ARCHITECTURE.md](docs/AI_ARCHITECTURE.md) | Investigation pipeline, provider abstraction, grounding/validation, safety, cost tracking |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Environments, configuration, Docker Compose, CI/CD |
| [DECISIONS.md](docs/DECISIONS.md) | Architecture decision records (ADRs) and trade-offs |
| [ROADMAP.md](docs/ROADMAP.md) | Phased roadmap, technical risks, Phase 1 checklist |

## Running the project

```bash
make env          # creates .env files from .env.example (never overwrites)
make up           # builds and starts postgres, redis, migrate, api, worker, beat, web; waits until healthy
```

- Web dashboard: http://localhost:3000 (create an account, then an organization)
- API docs (Swagger UI): http://localhost:8000/docs · readiness: http://localhost:8000/readyz
- Postgres is published on **55432** and Redis on **56379** to avoid clashing with other local projects.

### AI investigator

Off by default per organization. An admin enables it on the web under **AI** (provider, model, monthly budget, automatic investigation threshold, redaction).

- **Real analysis (Gemini, free tier):** create a key at https://aistudio.google.com/apikey, set `GEMINI_API_KEY` in `.env` and `make up`. Default model `gemini-3.8-flash`. On the free tier Google may use the data sent to improve its products (the settings page says so); a paid key avoids that. Claude is available too via `ANTHROPIC_API_KEY` + provider "Anthropic".
- Keys stay on the API/worker; they are never sent to the web or mobile app.
- **Without a key:** `AI_FAKE_ENABLED=true` (local only) offers the rule-based *demo analyzer*, labelled "Demo analyzer · not an LLM" everywhere. It is refused in production.
- `make ai-eval` runs the golden scenarios with the demo analyzer; `make ai-eval PROVIDER=gemini` scores the real model.

Developing outside Docker:

```bash
make api-venv     # Python 3.12 virtualenv with dev deps
make api-check    # ruff, mypy --strict, pytest (uses the compose postgres/redis)
make web-install
make web-dev      # Next dev server on :3000 (stop the compose `web` service first)
make web-check    # eslint, tsc, vitest, production build
make openapi      # re-export the API contract, then `cd apps/web && pnpm gen:api`
```

End-to-end tests (`apps/web/e2e`) need a browser once: `cd apps/web && pnpm exec playwright install chromium && pnpm e2e`.

Mobile: see [apps/mobile/README.md](apps/mobile/README.md) (`flutter run --dart-define=API_BASE_URL=http://localhost:8000`).

Demo data (clearly tagged DEMO everywhere):

```bash
make seed-demo OWNER=you@example.com      # demo org, services, alert rules; prints a demo ingest key
make loadgen KEY=dp_ingest_... INCIDENT_AFTER=120   # synthetic traffic; simulates a bad release after 2 min
```

## Prerequisites (verified on this machine, 2026-11-11)

| Tool | Found | Needed |
|---|---|---|
| Python | 3.12.16 (`python3.12`); system `python3` is 3.9 | 3.12 |
| Node / pnpm | 25.2.1 / 12.15.0 | Node 24 LTS recommended (pinned via `.nvmrc`) |
| Docker / Compose | 29.2.0 / v5.0.2 | ✓ |
| Java | OpenJDK 17 | ✓ for Android builds |
| Flutter / Dart | 3.47.9 / 3.13 (Homebrew) | ✓ iOS; Android needs cmdline-tools + licenses |
| Xcode | 26.1.1 | ✓ |
| uv | not installed | Recommended for Python deps |

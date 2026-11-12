# DevPulse — Deployment & Environments

## 1. Environments

| Env | Purpose | Data |
|---|---|---|
| `local` | Docker Compose on a dev machine | optional demo seed (`is_demo=true`) |
| `test` | CI: ephemeral Postgres/Redis service containers | fixtures only |
| `staging` | pre-production, real integrations in sandbox mode | synthetic load generator, flagged demo |
| `production` | customers | real telemetry only; demo seeding refused (`APP_ENV=production` guard) |

## 2. Configuration

All config via environment variables, validated at boot by `pydantic-settings` (missing required var → process exits with a clear message). `.env.example` documents every variable; `.env` is git-ignored.

| Variable | Example | Notes |
|---|---|---|
| `APP_ENV` | `local` | local/test/staging/production |
| `DATABASE_URL` | `postgresql+asyncpg://devpulse:devpulse@postgres:5432/devpulse` | host runs use `localhost:55432` (ADR-014) |
| `REDIS_URL` | `redis://redis:6379/0` | broker, pub/sub, rate limits |
| `JWT_SIGNING_KEY` | (32+ chars) | production refuses `change-me…` placeholders; key rotation (`JWT_PREVIOUS_KEYS`) not implemented yet |
| `REFRESH_REUSE_GRACE_S` | `10` | refresh-token reuse grace window (ADR-003) |
| `LOGIN_RATE_LIMIT` / `LOGIN_RATE_WINDOW_S` | `10` / `300` | per email+IP |
| `ENCRYPTION_KEY` | (Fernet key) | integration secrets at rest |
| `CORS_ORIGINS` | `http://localhost:3000` | |
| `AI_PROVIDER` / `AI_MODEL` | `anthropic` / `claude-sonnet-5-5` | `fake` for offline dev |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | — | server only |
| `FCM_CREDENTIALS_JSON` | path | optional; push disabled when unset |
| `SENTRY_DSN` | — | optional |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | optional |
| Mobile (`--dart-define`) | `API_BASE_URL`, `WS_BASE_URL`, `SENTRY_DSN` | no secrets in the app binary |
| Web | `API_INTERNAL_URL`, `SESSION_COOKIE_SECURE` (`false` only for plain-http local dev) | |

## 3. Docker Compose (local)

```mermaid
flowchart LR
  web[web :3000] --> api[api :8000]
  api --> pg[(postgres:16 :5432)]
  api --> redis[(redis:7 :6379)]
  worker[worker] --> pg & redis
  beat[beat] --> redis
  api & worker --> otel[otel-collector]
  otel --> prom[prometheus :9090] --> graf[grafana :3001]
```

- Every service has a `healthcheck` (`pg_isready`, `redis-cli ping`, `curl /readyz`); dependants use `depends_on: condition: service_healthy`.
- A one-shot `migrate` service runs `alembic upgrade head` before `api`/`worker` start.
- Only `migrate` declares the API image build; `api`, `worker`, `beat` reuse `devpulse-api:local` (avoids parallel builds of the same tag).
- Observability stack (OTel collector, Prometheus, Grafana) as a Compose **profile** is **not built yet** — planned with telemetry in Phase 2.
- Phase 1 status: postgres, redis, migrate, api, worker, beat, web all implemented and verified healthy with `make up`.
- Phase 3 adds `relay` (`python -m app.workers.relay`): outbox → Redis pub/sub + push dispatch. Several relays may run (rows are claimed with SKIP LOCKED). WebSockets are served by the `api` process at `/ws`; a load balancer in front must allow WebSocket upgrades (no sticky sessions needed — fan-out goes through Redis).

## 4. CI (GitHub Actions)

| Workflow | Trigger | Steps |
|---|---|---|
| `api.yml` | PRs; called by deploy | ruff, format check, mypy, pytest (as a non-superuser DB role, so RLS is enforced), migration round-trip, `alembic check`, OpenAPI drift |
| `web.yml` | PRs; called by deploy | lint, typecheck, vitest, build, Playwright critical flows with axe + CSP checks against compose |
| `mobile.yml` | PRs, main | analyze, tests (incl. accessibility audit) |
| `compose.yml` | PRs | `docker compose up --wait`, `/readyz`, login |
| `security.yml` | PRs, weekly | pip-audit, pnpm audit, gitleaks |
| `deploy-staging.yml` | push to main | runs `api.yml` + `web.yml`, then triggers both Render deploy hooks **for that commit**, waits until `/healthz` reports the commit, and runs `infra/scripts/smoke.sh` |

## 5. Staging on Render (Phase 6)

`render.yaml` (Blueprint) describes the whole environment. Free tier only:

| Resource | Render type | Notes |
|---|---|---|
| `devpulse-api` | web (Docker, free) | `python -m app.scripts.supervise`: migrations, then API + Celery (`-B`, solo pool) + outbox relay in one container — workers are paid on Render |
| `devpulse-web` | web (Docker, free) | Next.js BFF; calls the API's public URL |
| `devpulse-db` | Postgres (free) | **deleted by Render 30 days after creation** (14-day grace to upgrade); 1 GB; no backups |
| `devpulse-redis` | Key Value (free) | 25 MB, in memory only (a restart drops queued tasks); `noeviction` |

Free-tier behaviour to expect: services sleep after 15 minutes without traffic and take about a minute to wake; while asleep, rollups, alert evaluation and AI runs pause. 750 instance hours per month per workspace. Staging is for correctness, not load (`docs/LOAD_TEST.md`).

**One-time setup** (needs your Render and GitHub accounts):

1. Push the repository to GitHub. In Render: **New → Blueprint**, pick the repo; Render creates the four resources from `render.yaml` and asks for the `sync: false` values (leave `API_INTERNAL_URL`/`API_PUBLIC_URL` empty for now; `GEMINI_API_KEY` and `SENTRY_DSN` are optional).
2. After the first deploy, set `API_INTERNAL_URL` and `API_PUBLIC_URL` on `devpulse-web` to the API's URL (e.g. `https://devpulse-api.onrender.com`) and redeploy the web service.
3. For each service, copy its **Deploy Hook** URL (Settings) into GitHub → Settings → Environments → `staging` as secrets `RENDER_DEPLOY_HOOK_API` and `RENDER_DEPLOY_HOOK_WEB`, and add variables `STAGING_API_URL` and `STAGING_WEB_URL`.
4. Push to `main`: CI tests, deploys that commit, and smoke-tests it. Until step 3 is done the deploy job is skipped, not failed.

Secrets: `JWT_SIGNING_KEY`, `ENCRYPTION_KEY` (any 32+ chars; turned into a Fernet key) and `BFF_SHARED_SECRET` are generated by Render; the web service reads the BFF secret from the API service. `TRUSTED_PROXY_HOPS=1` because Render's proxy appends the client IP.

**Verified locally** (2026-11-12): the API image run exactly as on Render (`supervise`, `PORT=10000`, `APP_ENV=staging`, a `postgres://` URL, a non-Fernet `ENCRYPTION_KEY`, an ordinary non-superuser database role so RLS is enforced) passed `infra/scripts/smoke.sh` and all Playwright flows. **Not verified:** the Blueprint against Render's schema (needs the Render CLI/API with an account) and an actual Render deploy.

**Demo data on staging:** Render's free tier has no shell; seed from your machine with `DATABASE_URL` set to the database's *external* URL (`cd services/api`, then run `app.scripts.seed_demo --owner-email you@example.com` with that `DATABASE_URL`), then run the load generator against the API's public URL.

## 6. Production (beyond staging)

Same images, separate services: `api` (several, `WEB_CONCURRENCY` about the CPU count), `worker`, `beat` (one), `relay`; managed Postgres with PITR and an **ordinary (non-superuser, no BYPASSRLS) role** for the app; managed Redis with persistence; migrations as a pre-deploy job, backward-compatible with the previous release (expand/contract). Mobile release automation (Fastlane/Codemagic) and OIDC SSO remain open.

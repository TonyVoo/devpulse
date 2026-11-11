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

Path-filtered workflows:

| Workflow | Steps |
|---|---|
| `api.yml` | ruff, ruff format --check, mypy, pytest (Postgres+Redis services), alembic upgrade/downgrade round-trip, `alembic check` (no drift), export OpenAPI and fail on uncommitted diff |
| `web.yml` | pnpm install --frozen-lockfile, lint, typecheck, vitest, build, Playwright critical flows against compose |
| `mobile.yml` | *not created yet* — added together with the Flutter app (blocked on Flutter SDK, ROADMAP R1) |
| `compose.yml` | `docker compose up --wait`, smoke test `/readyz` and login |
| `security.yml` | dependency audit (pip-audit, pnpm audit), secret scan (gitleaks); container scan (trivy) still to add |

## 5. Production target (Phase 6)

Single region; containers for `api`, `worker`, `beat`, `web` on a managed container platform; managed PostgreSQL (PITR backups) and managed Redis; TLS at load balancer; WebSocket-capable LB with sticky-less design (Redis fan-out). Releases: image tagged by git SHA, migrations run as a pre-deploy job and must be backward-compatible with the previous app version (expand/contract). Mobile: Fastlane/Codemagic later; out of scope until Phase 6.

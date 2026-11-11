# DevPulse — Roadmap, Risks, Phase 1 Checklist

## 1. Roadmap

| Phase | Scope | Exit criteria (verified, not claimed) |
|---|---|---|
| **0 Planning** ✅ | Docs in `docs/` | Architecture, schema, API, mobile, AI, deployment, ADRs reviewed |
| **1 Foundation** ✅ | Monorepo scaffold, Compose (pg, redis, api, worker, web), config validation, auth (register/login/refresh/logout), orgs, memberships, RBAC, audit log core, error model, logging, CI; Flutter app shell (theme, router, auth flow, org select, secure storage); Next.js shell (BFF auth, org switch) | `make up` healthy; auth + RBAC + tenant-isolation tests green; mobile logs in against local API; CI green |
| **2 Core product** ✅ | Services CRUD, ingest keys, metrics ingestion + rollups, overview endpoint, alert rules + evaluation, incident lifecycle/timeline/comments, deployments + GitHub webhooks, correlation; mobile Overview/Services/Incidents/Deployments screens (online) | Synthetic load generator drives an alert → incident end-to-end; lifecycle tests green |
| **3 Realtime & mobile excellence** | Outbox relay, WS gateway, sync feed, Drift offline model, outbox writes, backoff, conflict handling, FCM, deep links, lifecycle, tablet layouts, integration tests | Airplane-mode ack replays correctly; WS drop → no lost/duplicate items; push tap cold-start opens incident |
| **4 AI** | Provider port + Anthropic/OpenAI/Fake adapters, context collector, evidence registry, investigation task, validation/repair, usage & budget, Copilot UI (mobile + web), follow-up chat with read-only tools, proposals/approval | Golden scenarios pass with FakeProvider in CI; schema/grounding tests green; manual eval run documented |
| **5 Web & polish** | Members/RBAC admin, alert rule builder with preview, integrations, AI config, audit log viewer, advanced charts & correlation timeline; accessibility & motion pass on mobile | Playwright critical flows green; a11y audit fixes landed |
| **6 Production readiness** | Security review, RLS, OIDC, rate-limit tuning, load test ingestion, perf profiling (Flutter DevTools, API p95), Sentry wiring, deployment pipeline, demo environment | Threat model documented; load test report; staging deploy reproducible from CI |

## 2. Technical risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | ~~Flutter SDK not installed~~ — **resolved**: Flutter 3.47.9 via Homebrew; Xcode 26.1 works (the earlier `xcodebuild` error was a wrong flag). Android cmdline-tools/licenses still pending | Android local builds | Install Android cmdline-tools and run `flutter doctor --android-licenses` (user action) |
| R2 | Workspace is a temporary, non-git folder | Work could be lost | Move project to a permanent folder and `git init` before Phase 1 |
| R3 | Dependency incompatibilities (Riverpod 2 vs 3 codegen, Drift + build_runner, Next major vs React 19, Node 25 non-LTS) | Broken builds | Pin versions after checking against installed SDKs; Node 24 LTS via `.nvmrc`; lockfiles committed; Renovate later |
| R4 | Sync feed correctness under concurrent commits (`change_seq` gaps) | Silent missed updates offline | Snapshot-xmin/safety-lag reads; dedicated concurrency test with interleaved transactions; periodic full reconcile (hash of ids+versions) |
| R5 | Tenant data leak via a forgotten filter | Severe | Scoped repositories, generated cross-tenant tests over every route, RLS in Phase 6, workers require explicit OrgContext |
| R6 | Postgres time-series performance | Slow charts | Rollups, point caps, partition pruning, `MetricsStore` interface for later swap (ADR-002) |
| R7 | LLM hallucination / overconfidence | Wrong guidance during incidents | Evidence registry + ref validation, confidence caps, "hypothesis" labelling, data-gap disclosure, human-only confirmation |
| R8 | Prompt injection via logs/commit messages | Misleading analysis | Data delimiting, read-only tools, no execution path |
| R9 | LLM cost/latency spikes | Budget overrun, slow UX | Token budget per run, monthly org budget, async runs with progress, timeouts/retries |
| R10 | iOS background limits, APNs/FCM setup | Stale data, no push | Correctness never depends on background; foreground delta sync; needs Firebase project from you (Phase 3) |
| R11 | WebSocket scaling & auth | Leaks or dropped connections | Short-lived tickets, Redis fan-out, heartbeat, per-org subscription checks |
| R12 | Scope size vs quality | Half-finished features | Phase exit criteria above; nothing marked done without tests; placeholders documented as such |

## 3. Phase 1 implementation checklist

Legend: ✅ done and verified · ⏳ not done (reason given)

**Repo & tooling**
- ✅ Permanent folder (`~/Desktop/devpulse`), `git init`, branch `phase-1/foundation`, `.gitignore`, `.editorconfig`, `.nvmrc` (24), `Makefile` (`make help`)
- ✅ `.env.example` documents every variable; `make env` creates local copies
- ⏳ Pre-commit hooks (ruff, gitleaks) — CI covers these; local hooks not added yet

**Infrastructure**
- ✅ Compose: postgres:16, redis:7, migrate (one-shot), api, worker, beat, web — healthchecks + `service_healthy`/`service_completed_successfully` dependencies; verified all healthy
- ✅ API and web Dockerfiles (multi-stage, non-root users)

**Backend foundation (`services/api`)**
- ✅ FastAPI 0.162, SQLAlchemy 2.1 async, Alembic, pydantic-settings, structlog, argon2-cffi, PyJWT, redis, Celery
- ✅ Validated settings (fails fast; production refuses placeholder JWT key), problem+json errors, JSON logs with request id, `/healthz`, `/readyz` (DB + Redis + migrations at head)
- ✅ Alembic baseline (users, organizations, memberships, invitations, refresh_tokens, devices, audit_logs); upgrade/downgrade round-trip + `alembic check` clean
- ✅ Auth: register, login (rate-limited), refresh rotation with reuse detection + grace window, logout, `/me`, sessions list/revoke, password change (signs out everywhere), device registration
- ✅ Organizations & memberships: create (creator = owner), list/get/update/soft-delete, invitations (create/list/revoke/accept, email-bound, single-use), role changes with rank rules, last-owner guard under row locks, leave org
- ✅ RBAC: role → permission constants, `require_org(permission)`, `OrgContext`, `OrgScopedRepository`
- ✅ Audit: `record()` in the same transaction for org/member/invitation changes; DB trigger makes the table append-only; paginated `GET /audit-logs`
- ✅ Celery worker + beat with a real scheduled task (purge expired refresh tokens), verified in the running stack
- ✅ Tests: 52 passing — auth, RBAC matrix, tenant isolation (generated from the OpenAPI route table), invitations, audit pagination, health, units; ruff + mypy `--strict` clean
- ✅ OpenAPI export → `packages/api-contract/openapi.json` (`make openapi`)
- ⏳ `Idempotency-Key` handling — moved to Phase 2 with the incident commands that need it
- ⏳ Invitation emails — Phase 3 (notifications); the API returns the token once for manual sharing

**Mobile foundation (`apps/mobile`)** — Flutter 3.47.9 installed via Homebrew (R1 resolved for iOS)
- ✅ `flutter create` (iOS + Android), `--dart-define` config (`API_BASE_URL`), strict analysis (strict casts/inference/raw types + extra lints), formatter width 120
- ✅ Design tokens (`DpPalette` ThemeExtension, spacing/radius/motion) mirrored from the web; dark + light Material themes; components `DpButton`, `DpTextField`, `DpBanner`, `DpEmptyState`, `DpLogo`
- ✅ Dio client: problem+json → typed `Failure`s; auth interceptor with proactive + reactive refresh, **single-flight** refresh shared by concurrent requests, no sign-out while offline; retry interceptor (GET only, exponential backoff with full jitter, honours `Retry-After`)
- ✅ Tokens in Keychain/Keystore (`flutter_secure_storage`), session restore with offline fallback to the cached profile ("stale" banner), sign-out wipes user data but keeps device preferences
- ✅ GoRouter with a pure, unit-tested redirect rule (deep link preserved through sign-in, open-redirect safe); `StatefulShellRoute.indexedStack` with 5 tabs; bottom bar on phones, navigation rail ≥ 840 dp
- ✅ Screens: splash (with retry), sign in, register, organization picker/create, Settings (profile, organization switch, theme, sign out with confirmation); Overview/Services/Incidents/Copilot show honest empty states (no fake data); pull-to-refresh; app-resume profile refresh
- ✅ Drift database (schema v1, key/value cache) with tests
- ✅ 39 unit/repository/widget tests passing; `flutter analyze` clean; iOS simulator debug build launches
- ⏳ Integration test against the real API (`integration_test/auth_flow_test.dart`) — see final status in the Phase 1 report
- ⏳ Android: SDK command-line tools + license acceptance missing on this machine (`flutter doctor`); CI builds the APK
- ⏳ Push (FCM), deep-link platform config (AASA/assetlinks), WebSocket, offline entity sync — Phase 3 as planned

**Web foundation (`apps/web`)**
- ✅ Next.js 16.4 (App Router) + React 19.3 + TS strict + Tailwind 4; tokens in `globals.css` mirror DESIGN_SYSTEM.md (dark-first + light)
- ✅ BFF: login/register/logout route handlers with httpOnly cookies; `/api/v1/*` proxy with CSRF double-submit, refresh-on-expiry and token-endpoint blocking; `proxy.ts` gate + proactive refresh
- ✅ TanStack Query provider, generated TS types from OpenAPI (`pnpm gen:api`)
- ✅ Pages: login, register, organizations (list + create), org overview (honest empty state), members (read-only), org switcher, sign out; narrow-screen top bar
- ✅ Vitest + Testing Library: 18 tests; eslint, `tsc`, production build clean
- ✅ Verified in a browser against the running stack (dark/light, 375px width) and by curl (refresh, CSRF, blocked paths)
- ⏳ Playwright critical flow is written (`e2e/auth-org.spec.ts`) and runs in CI; **not run locally** (Chromium download not installed on this machine)
- ⏳ Member management actions in the UI (invite, change role, remove) — API is ready; UI is Phase 5 admin work

**CI**
- ✅ `api.yml` (lint, mypy, migrations round-trip + drift, tests, OpenAPI drift), `web.yml` (contract drift, lint, typecheck, unit tests, build, Playwright e2e), `compose.yml` (full-stack smoke), `security.yml` (gitleaks, pip-audit, pnpm audit) — YAML validated locally; **not yet run on GitHub** (no remote configured)
- ✅ `mobile.yml` (generated-code drift, format, analyze, tests, Android APK build, iOS simulator build) — not yet run on GitHub

**Docs**
- ✅ README run commands, DECISIONS (ADR-003 refinements, ADR-013, ADR-014), schema/API/deployment status notes

## 4. Phase 2 checklist

Legend: ✅ done and verified · ⏳ not done (reason given)

**Backend**
- ✅ Services CRUD (soft delete, `If-Match`), ingest keys (scoped, optionally bound to a service, shown once, revocable, rate-limited)
- ✅ Metrics and logs ingestion with validation (timestamp window, label limits, NaN rejected), daily partitions + maintenance task, log fingerprints
- ✅ 1-minute rollups (dirty-minute set + safety sweep), metrics query API, org overview
- ✅ Alert rules CRUD + 24 h preview; evaluator with pending/firing/resolved, dedup, service health (ADR-017)
- ✅ Incidents: manual + alert-opened, per-org numbering (`INC-1001`), commands with state machine, `If-Match`, `Idempotency-Key`; timeline; idempotent comments; deployment correlation (system + user)
- ✅ Deployments: CI ingest (idempotent on `external_id`), list/detail, GitHub integration (Fernet-encrypted secret, HMAC verification, delivery dedup, repo → service mapping)
- ✅ Demo seed + synthetic load generator (ADR-018)
- ✅ 76 tests (incl. the generated tenant-isolation suite now covering every Phase 2 org route); ruff + mypy `--strict`; migration round-trip + `alembic check`
- ✅ Exit criterion verified in the running stack: load generator's bad release → worker opened INC-1001 (SEV2 latency) and INC-1002 (SEV1 error rate), checkout-api critical, both correlated to the deploy
- ⏳ OTLP-compatible ingest endpoint, `metric_rollups_1h`, DevPulse self-monitoring stack — not built
- ⏳ Grouping incidents across rules — future (ADR-017)

**Mobile** (online; offline sync is Phase 3)
- ✅ Overview (window switch, KPIs, health strip, request chart, critical banner, recent incidents/deployments)
- ✅ Services list (search, health filters kept across navigation) and detail (latency/error/requests/CPU charts with range picker, open incidents, deployments)
- ✅ Incidents list (status/severity/mine filters, cursor pagination with id de-duplication, pull-to-refresh) and detail (acknowledge/resolve/reopen/assign-to-me/escalate with `If-Match` + idempotency, conflict → reload + explanation, timeline, optimistic comments, suspected deployments)
- ✅ Deployments list; deep link `/incidents/INC-1042`
- ✅ 49 unit/widget tests; analyzer clean
- ✅ Real-API integration test (`integration_test/auth_flow_test.dart`) passes on the iPhone 17 Pro simulator
- ✅ Visual check on the simulator (dark mode) with live demo data: Overview, Services, service detail (1h and 24h), Incidents, incident detail. Fixed from it: overlapping/wrapping chart axis labels, charts bridging no-data periods with a straight line, invisible isolated points, a half-filled current minute looking like a traffic drop, default-purple filter chips, an unreadable error-rate alert summary

**Web**
- ✅ Overview with real data, Services (list + create), Ingest keys (create shown-once with curl example, revoke), Incidents (read-only list); checked in the browser against the demo org
- ✅ 25 vitest tests; lint, typecheck clean
- ⏳ Alert rule builder, GitHub integration UI, incident actions on web — Phase 5 (APIs exist)

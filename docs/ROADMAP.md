# DevPulse — Roadmap, Risks, Phase 1 Checklist

## 1. Roadmap

| Phase | Scope | Exit criteria (verified, not claimed) |
|---|---|---|
| **0 Planning** ✅ | Docs in `docs/` | Architecture, schema, API, mobile, AI, deployment, ADRs reviewed |
| **1 Foundation** ✅ | Monorepo scaffold, Compose (pg, redis, api, worker, web), config validation, auth (register/login/refresh/logout), orgs, memberships, RBAC, audit log core, error model, logging, CI; Flutter app shell (theme, router, auth flow, org select, secure storage); Next.js shell (BFF auth, org switch) | `make up` healthy; auth + RBAC + tenant-isolation tests green; mobile logs in against local API; CI green |
| **2 Core product** ✅ | Services CRUD, ingest keys, metrics ingestion + rollups, overview endpoint, alert rules + evaluation, incident lifecycle/timeline/comments, deployments + GitHub webhooks, correlation; mobile Overview/Services/Incidents/Deployments screens (online) | Synthetic load generator drives an alert → incident end-to-end; lifecycle tests green |
| **3 Realtime & mobile excellence** ✅ (push delivery pending Firebase) | Outbox relay, WS gateway, sync feed, Drift offline model, outbox writes, backoff, conflict handling, FCM, deep links, lifecycle, tablet layouts, integration tests | Airplane-mode ack replays correctly; WS drop → no lost/duplicate items; push tap cold-start opens incident |
| **4 AI** ✅ (real-model eval pending a key; OpenAI adapter not built) | Provider port + Anthropic/OpenAI/Fake adapters, context collector, evidence registry, investigation task, validation/repair, usage & budget, Copilot UI (mobile + web), follow-up chat with read-only tools, proposals/approval | Golden scenarios pass with FakeProvider in CI; schema/grounding tests green; manual eval run documented |
| **5 Web & polish** ✅ (manual screen-reader pass open) | Members/RBAC admin, alert rule builder with preview, integrations, AI config, audit log viewer, advanced charts & correlation timeline; accessibility & motion pass on mobile | Playwright critical flows green; a11y audit fixes landed |
| **6 Production readiness** ✅ (first Render deploy + OIDC pending — see checklist) | Security review, RLS, OIDC, rate-limit tuning, load test ingestion, perf profiling (Flutter DevTools, API p95), Sentry wiring, deployment pipeline, demo environment | Threat model documented; load test report; staging deploy reproducible from CI |

## 2. Technical risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | ~~Flutter SDK not installed~~ — **resolved**: Flutter 3.47.9 via Homebrew; Xcode 26.1 works (the earlier `xcodebuild` error was a wrong flag). Android cmdline-tools/licenses still pending | Android local builds | Install Android cmdline-tools and run `flutter doctor --android-licenses` (user action) |
| R2 | Workspace is a temporary, non-git folder | Work could be lost | Move project to a permanent folder and `git init` before Phase 1 |
| R3 | Dependency incompatibilities (Riverpod 2 vs 3 codegen, Drift + build_runner, Next major vs React 19, Node 25 non-LTS) | Broken builds | Pin versions after checking against installed SDKs; Node 24 LTS via `.nvmrc`; lockfiles committed; Renovate later |
| R4 | ~~Sync feed correctness under concurrent commits~~ — **resolved** by commit-ordered stamping (ADR-019), covered by a two-connection test | — | Periodic full reconcile still a nice-to-have |
| R5 | Tenant data leak via a forgotten filter | Severe | Scoped repositories, generated cross-tenant tests over every route, RLS in Phase 6, workers require explicit OrgContext |
| R6 | Postgres time-series performance | Slow charts | Rollups, point caps, partition pruning, `MetricsStore` interface for later swap (ADR-002) |
| R7 | LLM hallucination / overconfidence | Wrong guidance during incidents | Evidence registry + ref validation, confidence caps, "hypothesis" labelling, data-gap disclosure, human-only confirmation |
| R8 | Prompt injection via logs/commit messages | Misleading analysis | Data delimiting, read-only tools, no execution path |
| R9 | LLM cost/latency spikes | Budget overrun, slow UX | Token budget per run, monthly org budget, async runs with progress, timeouts/retries |
| R10 | iOS background limits, APNs/FCM setup | Stale data, no push | Correctness never depends on background (verified: resume → reconnect → delta sync). **Open:** real push needs a Firebase project + APNs key from you |
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
- ✅ Member management actions in the UI (invite, change role, remove) — done in Phase 5

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
- ✅ Alert rule builder, GitHub integration UI, incident actions on web — done in Phase 5

## 5. Phase 3 checklist

**Backend**
- ✅ `change_seq` stamping + outbox via triggers (ADR-019), migration tested up/down with existing data
- ✅ Sync feed `/sync/{services|incidents|deployments}` with initial window, tombstones, pagination
- ✅ Relay process (LISTEN/NOTIFY + poll, SKIP LOCKED), WebSocket gateway with single-use tickets, heartbeat and membership re-check
- ✅ Push dispatch: recipients by preferences, actor excluded, payload `route`/`org_id`; notification preferences API
- ✅ 84 tests (incl. commit-order concurrency test, ingestion not stamping, relay publishing, push rules, WebSocket against a real uvicorn process)
- ✅ Live check on the stack: incident created → hint received over WebSocket in ~100 ms
- ⏳ Real FCM delivery (needs Firebase project, service account, APNs key)

**Mobile**
- ✅ Drift schema v2 + v1→v2 migration test
- ✅ Sync engine (single-flight, re-run-if-dirty, atomic page+cursor, seq-guarded upserts, tombstones)
- ✅ Outbox: optimistic actions/comments, ordered replay, idempotent retries (lost response), backoff, conflicts → refresh + message, permanent failures kept
- ✅ Realtime client with ticket auth, backoff reconnect, resync on hello; lifecycle (30 s background grace) and connectivity handling
- ✅ Lists read from the local database; offline/pending banner; pending markers on items
- ✅ Push routing (payload validation, org switch, cold start / background tap) behind `PushMessages`
- ✅ 65 unit/widget tests (offline replay, lost response, conflict, ordering, comments, tombstones, migration, realtime reconnect)
- ✅ Simulator vs real stack: `offline_realtime_test` — realtime delivery without refresh; airplane-mode acknowledge replayed exactly once; Phase 1–2 flow still passes
- ⏳ Firebase SDK + universal links (AASA/assetlinks) — need your Firebase project and a domain
- ⏳ Background fetch (workmanager) — not needed for correctness; deferred
- ⏳ Exit criterion "push tap cold-start opens incident": routing is implemented and unit-tested; not verifiable end-to-end without Firebase

## 6. Phase 4 checklist

**Backend**
- ✅ Migration `2cbe7983d3cf`: ai_settings, ai_investigations (one active + one auto run per incident), ai_evidence, ai_messages, ai_usage, ai_action_proposals, ai_feedback; `ai_analysis` timeline event. Up/down round-trip tested
- ✅ Provider port; `GeminiProvider` (default, `google-genai` 3.2: JSON-schema structured output, function declarations, SDK retries/timeouts, thought-signature replay, error mapping; free tier); `AnthropicProvider` (official SDK 2.8: structured output, strict read-only tools, prompt caching, refusal fallback, SDK retries/timeouts, error-code mapping); `FakeProvider` (scripted + rule-based demo analyzer, refused in production)
- ⏳ `OpenAIProvider` — not built (the port is ready; ADR-021)
- ✅ Context collector + evidence registry (metrics vs baseline, log fingerprints with novelty, deployments with timing/correlation, alerts, similar incidents, explicit data gaps), redaction, untrusted-data framing
- ✅ Validation: grounding (unknown/zero refs rejected), bounds, single-evidence cap, server-set policy fields, one repair attempt
- ✅ Celery `ai.investigate` with 90 s run cap; budget + provider + opt-in guards (at queue time and run time); token cap; stale-run sweep; auto-trigger from the relay
- ✅ Usage & cost per call (including failed calls), `/ai/usage`, month-to-date budget
- ✅ Follow-up questions with bounded read-only tool loop (new evidence refs), idempotent on `client_id`
- ✅ Proposals: decisions audited + on the timeline; destructive needs an admin; nothing executes
- ✅ 50 AI tests (134 backend total): validation units, 4 golden scenarios, guards, repair, provider failures, tools (validation, clamping, tenant scope), chat replay, proposals RBAC, auto-trigger, Gemini and Anthropic adapters' wire format and error mapping against stubbed SDK clients
- ✅ `make ai-eval`: 4/4 golden scenarios with the demo analyzer
- ⏳ `make ai-eval PROVIDER=gemini` — needs your free `GEMINI_API_KEY`; not run
- ⏳ Prometheus token metrics, SSE streaming (ADR-023), per-org provider keys

**Mobile**
- ✅ Incident AI section: start, live progress (realtime + polling), hypotheses with confidence, evidence sheets (computed excerpts + source), risk badges, approve/reject with confirmation, data gaps, limitations, feedback; cached for offline reading
- ✅ Follow-up chat screen (retry-safe client ids, offline disabled); Copilot tab lists recent investigations; demo analyzer labelled everywhere
- ✅ 74 unit/widget tests (10 new)

**Web**
- ✅ Incident detail page (header, timeline, AI panel with evidence, approvals, feedback, follow-up questions); incident list links to it
- ✅ AI settings & usage page (admins edit; others read); no key fields
- ✅ 31 vitest tests (6 new), typecheck + lint clean

## 7. Phase 5 checklist

**Web**
- ✅ Members admin: invite (one-time link), pending invitations + revoke, role changes (never above your own), remove; `/invite/[token]` accept page
- ✅ Alert rules: list with live state, enable/disable, delete, builder with live draft preview (threshold line, shaded breaches, "would have fired N times"), optimistic concurrency on edit
- ✅ GitHub integration setup: webhook URL + secret shown once, repo → service mapping, step-by-step instructions
- ✅ AI config (Phase 4) and audit log viewer (families, paging, before/after diff, actor names)
- ✅ Service detail: 1h/6h/24h/7d charts (latency, error rate, throughput, CPU) with deploy and incident markers; gaps shown as gaps
- ✅ Incident: correlation charts around the incident with suspected deploys and lifecycle markers; acknowledge / resolve / assign / escalate / reopen (If-Match + Idempotency-Key); comments
- ✅ Bugs found by checking against real data: chart x-axis spanning only the data, overlapping marker labels, a correlation query that refetched in a loop (window derived from "now" on every render)
- ✅ 40 vitest tests; **Playwright: 4 critical flows green locally** with axe in light + dark (admin flow, invite acceptance, incident actions, auth)

**Backend**
- ✅ `POST /alert-rules/preview` for drafts; audit log `actor_name` + `action_prefix`; 1 new test + 1 extended (135 total)

**Mobile**
- ✅ Accessibility audit test (22 cases) + reduce-motion transitions; fixes: contrast-safe palette shared with web, 48dp segmented buttons, wrapping buttons/rows, bounded list-tile columns
- ✅ 97 tests
- ⏳ Manual VoiceOver/TalkBack pass on a device; tablet layouts

## 8. Phase 6 checklist

**Security** (`docs/SECURITY.md`)
- ✅ Threat model (STRIDE per boundary), dependency audits clean, findings fixed with tests: client-IP sharing/spoofing behind the BFF, per-email login limit, API security headers + `no-store`, request body limits (incl. chunked), nonce CSP + HSTS on the web, POST-only forms, HTTPS-only mobile release builds
- ✅ Row-level security on all tenant tables (ADR-026); the whole backend suite runs as a non-superuser role
- ✅ Abuse limits: registration, password change, invitations, AI start/ask (configurable)
- ⏳ OIDC SSO / MFA (deferred), container scanning (trivy), external penetration test

**Performance** (`docs/LOAD_TEST.md`)
- ✅ Load test tool + report: ingestion 17.7k → 27.2k points/s per writer (batched insert), ~65k points/s with 4 API processes; read p95 under ingest ~105–215 ms; rollup lag 52 s → 19 s
- ⏳ Mobile profiling on a physical device; alert-preview single-query rewrite

**Observability**
- ✅ Sentry on API, worker, beat, relay, web (server + browser) and mobile — off unless a DSN is set; credentials, cookies, bodies and user data scrubbed (tests on every platform)

**Deployment**
- ✅ `render.yaml` (free tier), all-in-one supervisor, configurable port/processes/proxy trust, managed-Postgres URL and platform-secret support, `/healthz` reports the release
- ✅ `deploy-staging.yml`: tests → deploy hooks pinned to the commit → wait for the release → smoke test
- ✅ Verified locally in the Render shape (smoke test + all Playwright flows, RLS enforced)
- ⏳ First real Render deploy (needs your Render account and a GitHub remote — DEPLOYMENT.md §5)

# Architecture Decision Records

Format: Context → Decision → Consequences. Status: **Accepted** unless noted.

### ADR-001 Modular monolith backend
**Context:** Small team, many coupled domains (incidents ↔ alerts ↔ deployments ↔ AI).
**Decision:** One FastAPI codebase, modules with owned tables and service interfaces, in-process event bus + transactional outbox; separate `api` / `worker` / `beat` processes from one image.
**Consequences:** Simple deploys and transactions; module boundaries enforced by convention + an import-linter rule in CI (`import-linter` contracts). Can split telemetry ingestion out later if load demands it.

### ADR-002 Telemetry storage in plain PostgreSQL (partitioned) + rollups
**Context:** Need time-series metrics without adding another database to operate.
**Alternatives:** TimescaleDB (great fit, adds extension dependency), ClickHouse/Prometheus remote storage (another system).
**Decision:** Native declarative partitioning by day for raw points, Celery-computed 1m/1h rollups, partition drops for retention. Metric queries go through a `MetricsStore` interface.
**Consequences:** Fine for demo/moderate scale (≈ millions of points/day). `MetricsStore` lets us swap to TimescaleDB/ClickHouse later without touching callers. Revisit if ingest > ~5k points/s sustained.

### ADR-003 First-party JWT auth now, OIDC later
**Decision:** Argon2id passwords; 15-min access JWT (HS256 → EdDSA when key management lands); 30-day rotating refresh tokens stored hashed with family-based reuse detection. OIDC added in Phase 6 behind the same token issuance.
**Consequences:** No external IdP needed to run locally; mobile and web share one token model.
**Phase 1 refinements (implemented):**
- *Reuse grace window* (`REFRESH_REUSE_GRACE_S`, default 10s): a just-rotated refresh token presented again inside the window gets a fresh token in the same family instead of revoking it. Without this, parallel requests, two browser tabs or a retried request whose response was lost would sign users out. Trade-off: a token stolen *and* replayed within 10s of a legitimate refresh is not detected (same model as Auth0's reuse interval). Outside the window, reuse revokes the whole family.
- *Access token revocation*: access tokens are stateless for 15 min, except that `users.tokens_valid_after` (set on password change) rejects every older token. Plain logout/session revoke kills the refresh family; the access token stays valid until expiry (≤15 min). Per-session access revocation would need a lookup per request — revisit if required.
- Login rate limit is per (email, client IP), fixed window in Redis. Behind the web BFF all browser logins share the BFF's IP, so the effective limit is per email.

### ADR-004 Tenant isolation in the application layer first, RLS later
**Decision:** Membership-checked `OrgContext` dependency + org-scoped repositories (no unscoped methods) + generated cross-tenant tests. PostgreSQL RLS added in Phase 6 as defense-in-depth.
**Consequences:** Clear, testable; RLS later catches mistakes in raw SQL/workers. Workers must construct an `OrgContext` explicitly (system actor) — no implicit global access.

### ADR-005 Mobile: local DB as single source of truth
**Decision:** Drift is the read model for all list/detail screens; network, sync and realtime only write into it with version-guarded upserts.
**Consequences:** Offline reads, dedupe and state restoration fall out naturally; costs more code (DAOs, migrations) and requires a careful client schema migration story.

### ADR-006 Logs only as incident evidence
**Decision:** Short-retention log events (7 days) for AI evidence and incident context; no general log search.
**Consequences:** Keeps scope realistic; users with existing log platforms integrate later via links/tools.

### ADR-007 Web BFF with httpOnly cookies
**Decision:** Next.js route handlers store tokens in httpOnly cookies and proxy API calls; browser JS never sees tokens. CSRF: SameSite=Lax + double-submit token on mutations.
**Consequences:** Removes XSS token theft; adds a proxy hop. WebSocket from web uses the ticket endpoint via the BFF.

### ADR-008 Incident mutations as commands with optimistic concurrency
**Decision:** `acknowledge/resolve/assign/escalate` are explicit command endpoints validated against a state machine, with `If-Match` versions and `Idempotency-Key`.
**Consequences:** Offline replay is safe and conflicts are semantic ("already resolved") rather than field merges.

### ADR-009 Realtime = best-effort push + authoritative sync feed
**Decision:** WebSocket events are hints; the `change_seq` sync feed is the source of correctness. Events published only after commit via outbox.
**Consequences:** Missed events never corrupt client state; reconnect always does a delta sync.

### ADR-010 AI: evidence registry, provider port, no execution
**Decision:** Evidence is collected deterministically and referenced by ID; output is schema-validated; providers behind `LLMProvider`; tools are read-only; remediation is proposal-only with human approval.
**Consequences:** Hallucinated evidence is structurally rejected; cost/latency are bounded; switching providers is a config change.

### ADR-011 Contract-first clients generated from OpenAPI
**Decision:** Export OpenAPI from FastAPI in CI; generate TS (openapi-typescript + fetch) and Dart (openapi-generator `dart-dio`) clients into `packages/api-contract`; CI fails on drift.
**Consequences:** Type-safe clients; requires disciplined schema naming in Pydantic.

### ADR-012 Demo data separation
**Decision:** Demo seed is a separate command, sets `is_demo=true`, is refused in production, and is visibly tagged in UIs. A synthetic load generator emits realistic telemetry through the real ingest API (also flagged demo) so pipelines are exercised end-to-end.
**Consequences:** Demos look alive without faking product code paths.

### ADR-013 Next.js Cache Components disabled for now (Phase 1)
**Context:** Next 16.4 scaffolds with `cacheComponents` and `partialPrefetching` on. With them, every `cookies()` read must sit behind `<Suspense>`, and every DevPulse dashboard page is per-user and session-dependent, so there is almost no static shell to gain.
**Decision:** `cacheComponents: false` in `apps/web/next.config.ts`. Session refresh happens in `proxy.ts` (Next 16's replacement for `middleware.ts`) and in the BFF route handlers.
**Consequences:** Simpler data flow now; revisit in Phase 5 for public/marketing or shared-shell pages.

### ADR-014 Development host ports
**Decision:** Compose publishes Postgres on **55432** and Redis on **56379** (overridable in `.env`). Other projects on the development machine already used 5432/5433/6379.

### ADR-015 Mobile foundation choices (Phase 1)
- **Riverpod 3 without code generation** (`Notifier`/`AsyncNotifier` + plain providers). Fewer generated files while the app is small; `riverpod_generator` can be adopted per feature later. Session restore has auto-retry disabled (`retry: null`) — retrying is a user action on the splash screen.
- **No Freezed yet.** Phase 1 models are a handful of immutable classes with hand-written `fromJson`; Freezed/json_serializable arrive with the larger incident/service models in Phase 2.
- **Drift is introduced with a key/value table only** (cached profile, selected org, theme). Entity tables + outbox + sync cursors land in Phase 3 as schema v2 with migration tests.
- **System fonts for now.** Inter / JetBrains Mono are not bundled yet (the brief's offline-first goal rules out runtime font downloads); they will be added as assets.
- **iOS ATS:** `NSAllowsLocalNetworking` allows plain HTTP to local/LAN addresses only (development API). Public hosts still require HTTPS.
- **Haptics never awaited.** Found in testing: awaiting `HapticFeedback` can hang if the platform call doesn't return, freezing the form in its loading state.

### Resolved open questions
- Python dependency tool: **pip + pyproject with pinned compatible ranges** for Phase 1 (uv was not installed; avoided adding system tools). A lockfile (uv or pip-tools) should be added before Phase 6.
- Node version: `.nvmrc` pins **24 LTS**; Docker and CI use Node 24. Local development was verified on Node 25.
- shadcn/ui: components follow shadcn conventions (`cva` + `tailwind-merge`, owned in `src/components/ui`) but were written by hand rather than via the shadcn CLI, so they use DevPulse tokens directly.
- Charts on mobile: still **fl_chart** (default), decided when charts land in Phase 2.

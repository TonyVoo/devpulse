# DevPulse — API Contract (v1)

**Implemented:** Phase 1 — §2 (auth, `/me`, sessions, devices; `/me/notification-preferences` not yet), §3, §9. Phase 2 — §4 (overview, services + `PATCH`/`If-Match`, ingest keys, service metrics, incidents with commands/timeline/comments/correlation, deployments, alert rules + preview, GitHub integration), §5 (metrics, logs, deployments ingestion). Phase 3 — §6 sync feed, §7 realtime (ticket + WebSocket), notification preferences (`GET|PUT /orgs/{org_id}/notification-preferences`; per user and org: `push_enabled`, `min_severity`, `only_assigned`). Not yet: §8 AI. Everything else is the target contract. The live schema is `packages/api-contract/openapi.json` (CI fails if it is stale).

**Web BFF routes** (Next.js, same origin as the dashboard — browser never sees tokens):
`POST /api/auth/login|register` (JSON only → sets httpOnly cookies, returns `{user}`), `POST /api/auth/logout` (CSRF header required), `GET|POST|PATCH|PUT|DELETE /api/v1/*` (proxy to the API with the session; `x-csrf-token` required on mutations; `auth/*` and `me/password` blocked because their responses carry tokens).

The FastAPI app is the source of truth; `openapi.json` is exported in CI to `packages/api-contract` and Dart/TS clients are generated from it. This document defines conventions and the endpoint surface; field-level schemas live in OpenAPI.

## 1. Conventions

| Topic | Rule |
|---|---|
| Base | `/api/v1` (user API), `/ingest/v1` (telemetry, ingest-key auth), `/webhooks/*` (signed) |
| Auth | `Authorization: Bearer <access JWT>` (15 min). Ingest: `Authorization: Bearer dp_ingest_…` |
| Tenancy | Org-scoped routes under `/api/v1/orgs/{org_id}`; membership verified server-side on every request |
| IDs | UUIDv7 strings; incidents also expose `number` (`INC-1024`) |
| Time | RFC 3339 UTC |
| Pagination | Cursor (keyset): `?limit=50&cursor=<opaque>` → `{items, next_cursor}`; `limit` ≤ 200 |
| Filtering | Explicit query params (`status=triggered,acknowledged&severity=sev1`); `q` for text search |
| Concurrency | Responses carry `ETag: "<version>"`; state-changing commands accept `If-Match`; mismatch → `409` with current resource |
| Idempotency | `Idempotency-Key` header on all POST commands; server stores (key, user, response) 24h |
| Errors | RFC 9457 `application/problem+json`: `{type, title, status, detail, code, request_id, errors?}` |
| Rate limits | Per-user and per-ingest-key token bucket (Redis); `429` + `Retry-After` |
| Versioning | Breaking changes → `/api/v2`; additive changes allowed in v1; clients ignore unknown fields |

Stable error codes (examples): `auth.invalid_credentials`, `auth.token_expired`, `auth.refresh_reused`, `org.not_found`, `rbac.forbidden`, `incident.invalid_transition`, `conflict.version_mismatch`, `validation.failed`, `ai.disabled`, `ai.budget_exceeded`, `rate_limited`.

## 2. Auth & identity

| Method | Path | Notes |
|---|---|---|
| POST | `/auth/register` | email, password, display_name → user + tokens |
| POST | `/auth/login` | → `{access_token, refresh_token, expires_in, user}` |
| POST | `/auth/refresh` | rotating refresh; reuse of a rotated token outside the 10s grace window revokes the family (ADR-003) |
| POST | `/auth/logout` | revokes current refresh family; unregisters device |
| GET | `/me` | profile + memberships `[{org, role}]` |
| PATCH | `/me` | display name, theme |
| POST | `/me/password` | change password; revokes other sessions |
| GET/DELETE | `/me/sessions[/{id}]` | list / revoke sessions (security settings) |
| POST | `/me/devices` | register FCM token `{platform, fcm_token, app_version}` |
| GET/PUT | `/me/notification-preferences` | per org |

OIDC (`/auth/oidc/{provider}/start|callback`) is a Phase 6 addition behind the same token issuance.

## 3. Organizations, members, RBAC

| Method | Path | Permission |
|---|---|---|
| POST | `/orgs` | any user (creator becomes owner) |
| GET/PATCH/DELETE | `/orgs/{org_id}` | read / org.manage |
| GET | `/orgs/{org_id}/members` | read |
| GET/POST | `/orgs/{org_id}/invitations` | members.manage — POST returns the invite `token` once; email delivery arrives with notifications (Phase 3) |
| DELETE | `/orgs/{org_id}/invitations/{id}` | members.manage |
| POST | `/invitations/{token}/accept` | authenticated |
| PATCH/DELETE | `/orgs/{org_id}/members/{user_id}` | members.manage (cannot remove last owner) |
| GET | `/orgs/{org_id}/audit-logs?action=&action_prefix=&cursor=` | audit.read — entries include `actor_name`; `action_prefix` filters a family (e.g. `member.`) |

## 4. Product resources (all under `/orgs/{org_id}`)

**Overview**
- `GET /overview?window=1h|24h|7d` → service counts by health, open incidents by severity, request volume, error rate, avg/p95 latency (computed from rollups), recent deployments (5), recent incidents (5).

**Services**
- `GET /services?health=&environment=&q=&cursor=` · `POST /services` · `GET|PATCH|DELETE /services/{id}`
- `GET /services/{id}/metrics?names=http.server.duration_ms:p95,http.server.errors:rate&from=&to=&step=1m|5m|1h` → series `[{name, points:[[ts, value]]}]`; server chooses raw/1m/1h source by range and caps points at 500 per series.
- `GET|POST|DELETE /ingest-keys` (key shown once at creation)

**Incidents**
- `GET /incidents?status=&severity=&service_id=&assignee=me&cursor=` · `POST /incidents` (manual)
- `GET /incidents/{id}` (accepts UUID or `INC-1024`)
- Commands (POST, `If-Match` + `Idempotency-Key`):
  `/incidents/{id}/acknowledge` · `/resolve {resolution_note?}` · `/reopen` · `/assign {user_id}` · `/escalate {reason?}` · `/severity {severity}`
  Invalid transitions → `409 incident.invalid_transition`.
- `GET /incidents/{id}/timeline?cursor=` (incident_events)
- `GET|POST /incidents/{id}/comments` (POST carries `client_id` for idempotent offline posting)
- `GET /incidents/{id}/deployments` (correlated, with score) · `PUT /incidents/{id}/deployments/{dep_id} {correlation}`

**Deployments**
- `GET /deployments?service_id=&status=&from=&to=&cursor=` · `GET /deployments/{id}`
- `POST /ingest/v1/deployments` (ingest key; CI pipelines) — idempotent on `external_id`

**Alert rules** — `GET|POST /alert-rules`, `GET|PATCH|DELETE /alert-rules/{id}`, `POST /alert-rules/{id}/preview` (evaluates against last 24h, returns would-have-fired windows), `POST /alert-rules/preview?hours=` (Phase 5: same replay for an unsaved draft — body is a full rule; nothing is stored; the service must belong to the org).

**Integrations** — `GET|POST /integrations`, `PATCH|DELETE /integrations/{id}`, `POST /integrations/{id}/test`. GitHub webhook: `POST /webhooks/github/{integration_id}` verified with `X-Hub-Signature-256` HMAC (constant-time compare), deduped on `X-GitHub-Delivery`. Handles `deployment`, `deployment_status`, `workflow_run`, `push`.

### Phase 2 behaviour notes
- `GET …/services/{id}/metrics?names=<metric>:<agg>&from=&to=&step=` — aggregations `avg|sum|min|max|count|p50|p95|p99`; `http.server.error_rate` is derived (errors ÷ requests, aggregation `ratio`). Step is chosen automatically (≤ 250 points) unless given; percentiles for steps > 1 min are approximate (`approximate_percentiles: true`). Missing buckets are omitted — clients draw gaps, never zeros (the mobile app inserts explicit breaks where buckets are more than 1.5 steps apart and draws isolated points as dots). Series end at the last complete minute so a half-filled current minute never looks like a drop; `to` later than that is clamped.
- `GET …/overview?window=1h|24h|7d` — service health counts, open incidents by severity, request/error/latency totals (null = no data), a request-volume series, 5 recent incidents and deployments.
- Incident commands (`acknowledge|resolve|reopen|assign|escalate|severity`) accept `If-Match: "<version>"` (409 `conflict.version_mismatch` with `current_version`) and `Idempotency-Key` (replays return the stored response with `Idempotent-Replayed: true`; reusing a key for a different request → 422 `idempotency.key_reused`). Invalid transitions → 409 `incident.invalid_transition`.
- Comments are idempotent on `client_id` (201 first time, 200 with the original on retry).
- `POST /webhooks/github/{integration_id}` handles `ping`, `deployment`, `deployment_status`; signature failure and unknown integration both return 401 `webhook.invalid_signature`.

## 5. Telemetry ingestion

`POST /ingest/v1/metrics`
```json
{ "service": "checkout-api", "environment": "prod",
  "points": [ { "name": "http.server.duration_ms", "ts": "2026-11-11T10:00:00Z",
                "value": 182.4, "labels": { "route": "/pay" } } ] }
```
Limits: ≤ 1000 points, ≤ 1 MB, labels ≤ 20 keys, timestamps within [now-1h, now+5m]. Returns `202 {accepted: n}`. Unknown service with a key scoped `services:autocreate` creates it; otherwise `422`.

`POST /ingest/v1/logs` — same envelope with `{ts, level, message, attributes, trace_id}`.

## 6. Incremental sync (mobile offline) — implemented

`GET /orgs/{org_id}/sync/{collection}?cursor=<int>&limit≤500` for `collection ∈ {services, incidents, deployments}`

```json
{ "collection": "incidents",
  "changes": [ { "op": "upsert", "id": "…", "change_seq": 812, "data": { …same shape as GET … } },
               { "op": "delete", "id": "…", "change_seq": 815, "data": null } ],
  "next_cursor": 815, "has_more": false }
```
- `cursor` is the last `change_seq` the client stored (0 = first sync). Rows come in `change_seq` order; `change_seq` is commit-ordered per org (ADR-019), so resuming from `next_cursor` never skips a change.
- First sync (`cursor=0`) ships what a phone needs: non-deleted services, open incidents + incidents resolved in the last 7 days, deployments from the last 7 days. Anything older still arrives later if it changes.
- Deleted services arrive as `delete` tombstones (services are soft-deleted). Incidents and deployments are never deleted.
- Clients should store each page and its cursor atomically and only replace a cached row with a higher `change_seq`.

## 7. Realtime (WebSocket) — implemented

- `POST /api/v1/realtime/ticket {"org_id"}` (bearer; membership checked, 404 otherwise) → `{ticket, expires_in: 30, path: "/ws"}`. Single use.
- `GET /ws?ticket=…` → first frame `{"type":"hello","org_id":…,"server_time":…}`.
- Server → client frames:
  - `{"type":"sync","collection":"services|incidents|deployments","id":…,"change_seq":N}` — something in that collection changed; delta-sync if `N` is above your cursor.
  - `{"type":"incident_event","event":"created|acknowledged|comment_added|…","incident_id":…,"event_id":…,"actor_id":…}` — timeline changed (useful for an open detail screen).
  - `{"type":"ping"}` every 25 s.
- Close codes: `4401` invalid/expired ticket (get a new one), `4403` membership revoked.
- Delivery is at-least-once and best-effort; always delta-sync after (re)connecting.

## 8. AI ✅ Phase 4

All under `/orgs/{org_id}`. Errors use stable codes: `ai.disabled`, `ai.provider_unconfigured` (503), `ai.budget_exceeded`, `ai.already_running` (409, includes `investigation_id`), `ai.not_ready`, `ai.investigation_not_found`, `ai.proposal_decided`, `ai.destructive_requires_admin` (403), provider failures as 502 with the provider code (`ai.refused`, `ai.invalid_output`, `ai.rate_limited`, …).

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/incidents/{ref}/investigations` | ai.investigate | `202` → investigation (`queued`); one active run per incident |
| GET | `/incidents/{ref}/investigations` | org.read | latest 20 runs (summaries) |
| GET | `/ai/investigations?limit=&cursor=` | org.read | org-wide, newest first (Copilot tab) |
| GET | `/ai/investigations/{id}` | org.read | result + evidence + proposals + `my_feedback` |
| GET | `/ai/investigations/{id}/messages` | org.read | follow-up conversation (user / tool / assistant) |
| POST | `/ai/investigations/{id}/messages` | ai.investigate | `{question, client_id}` → `{messages, new_evidence}`; synchronous, idempotent on `client_id` |
| POST | `/ai/investigations/{id}/proposals/{p_id}/decision` | ai.investigate (destructive: org.manage) | `{approve, note?}`; records a decision, executes nothing |
| PUT | `/ai/investigations/{id}/feedback` | org.read | `{helpful, note?}` (one per user, upsert) |
| GET | `/ai/settings` | org.read | includes effective provider/model, which providers the server has configured, month-to-date cost |
| PUT | `/ai/settings` | ai.configure | enable, provider, model, monthly budget, auto-investigate threshold, redaction. Provider API keys are server env only — never accepted or returned |
| GET | `/ai/usage?from=&to=` | ai.configure | calls, tokens and cost per day × model |

Result schema: see AI_ARCHITECTURE.md §4 (plus `adjustments`, and `proposal_id` on actions that need approval). Clients learn about finished runs from the incident's `ai_analysis` timeline event (WebSocket hint) or by polling while a run is active.

## 9. Health

`GET /healthz` (process alive) · `GET /readyz` (DB + Redis reachable, migrations at head) · `GET /metrics` (Prometheus, internal network only).

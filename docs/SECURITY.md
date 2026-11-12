# DevPulse — Security review & threat model (Phase 6)

Scope: API (FastAPI), workers (Celery, relay), web BFF (Next.js), mobile app (Flutter), Postgres, Redis, AI provider calls, GitHub webhooks, Render staging. Method: STRIDE per trust boundary, code review against the list below, automated scans, and tests for every fix.

## 1. Assets and trust boundaries

| Asset | Where | Why it matters |
|---|---|---|
| Accounts, sessions (refresh tokens, JWTs) | Postgres (hashed), httpOnly cookies, mobile secure storage | account takeover |
| Tenant data: incidents, telemetry, logs, AI analyses | Postgres | cross-tenant leak = the worst failure for a multi-tenant SaaS |
| Ingest keys, GitHub webhook secrets | Postgres (sha256 / Fernet-encrypted) | data injection, forged deployments |
| AI provider key, budget | server env | spend, prompt-injection-driven actions |
| JWT signing key, encryption key, BFF shared secret | server env | forge sessions / decrypt secrets / spoof client IPs |

```
Browser ──HTTPS──▶ Web BFF (Next.js) ──HTTPS + BFF secret──▶ API ──▶ Postgres (RLS) / Redis
Mobile ──HTTPS + Bearer──────────────────────────────────▶ API ──▶ AI provider (outbound only)
Services ──HTTPS + ingest key──▶ /ingest            GitHub ──HMAC-signed──▶ /webhooks/github
```

## 2. STRIDE

| Threat | Boundary | Mitigation (✅ implemented · ⚠️ accepted risk · ⏳ open) |
|---|---|---|
| **S**poofing a user | login | ✅ argon2id, generic errors, timing-equalised missing-user path; ✅ login limit per email+IP **and per email from any IP** (Phase 6); ⏳ OIDC/SSO and MFA (deferred) |
| Spoofing via stolen refresh token | sessions | ✅ rotation with reuse detection → whole family revoked (10 s grace for parallel tabs) |
| Spoofing a client IP to dodge rate limits | BFF → API, proxies | ✅ (Phase 6 fix) BFF forwards the browser IP only with a shared secret; behind proxies only the N rightmost (proxy-appended) `X-Forwarded-For` entries count |
| Spoofing a service / GitHub | ingest, webhooks | ✅ hashed scoped ingest keys (optional service binding); ✅ HMAC-SHA256 verified with constant-time compare; delivery dedup |
| **T**ampering with tenant data | API | ✅ `require_org` membership + permission checks, generated cross-tenant test over every org route; ✅ **Postgres row-level security** on all 28 tenant tables (Phase 6, ADR-026) |
| Concurrent / replayed writes | incident commands | ✅ `If-Match` versions, `Idempotency-Key`, comments idempotent on `client_id` |
| CSRF | web | ✅ double-submit token + SameSite=Lax + JSON-only credential routes; ✅ forms are `method="post"` (a no-JS fallback can never put a password in a URL — found in Phase 6) |
| XSS | web | ✅ React escaping, no `dangerouslySetInnerHTML`; ✅ **nonce-based CSP** with `strict-dynamic`, no third-party origins (Phase 6) |
| Clickjacking | web, API | ✅ `frame-ancestors 'none'` + `X-Frame-Options: DENY` |
| **R**epudiation | admin actions | ✅ append-only audit log (DB trigger) with actor, before/after; AI proposals' decisions audited |
| **I**nformation disclosure across tenants | DB | ✅ RLS (above); ✅ AI tools run through org-scoped queries; ✅ 404 (not 403) for other orgs |
| Disclosure via caches / logs / error reports | API, Sentry | ✅ `Cache-Control: no-store` on all `/api` responses (Phase 6); ✅ no headers/bodies in logs; ✅ Sentry scrubs credentials, cookies, bodies, users on every platform (Phase 6) |
| Disclosure of AI provider keys | clients | ✅ server env only; never accepted or returned by the API (tested) |
| Data sent to AI providers | AI | ✅ per-org opt-in, redaction of emails/IPs/secrets; ⚠️ Gemini free tier may use prompts to improve Google's products — warned in settings |
| Plaintext transport | mobile | ✅ release builds refuse non-HTTPS API URLs (Phase 6); iOS ATS allows only local networking |
| **D**enial of service: huge bodies | API | ✅ (Phase 6) 1 MB body limit (5 MB for ingest), enforced while streaming, 413 before parsing |
| DoS / cost: abuse of expensive endpoints | API | ✅ (Phase 6) limits on registration (per IP), password change, invitations (per org), AI start/ask (per user) on top of the org AI budget; ✅ per-key ingest limit; ⏳ global rate limiting at the edge (platform) |
| DoS: slow alert preview (289 queries) | API | ⚠️ read-only, 24 h max, admins only; ⏳ batch into one query |
| **E**levation of privilege | RBAC | ✅ fixed roles, can't grant above own role, last owner protected, destructive AI proposals need admin |
| Prompt injection → actions | AI | ✅ untrusted data framed as data; tools are read-only; proposals never execute |

## 3. Automated checks

| Check | Result (2026-11-12) | Where |
|---|---|---|
| `pip-audit` (Python deps) | no known vulnerabilities | `security.yml` weekly + PRs |
| `pnpm audit --prod` | no known vulnerabilities | `security.yml` |
| gitleaks (secrets in history) | in CI | `security.yml` |
| ruff `S` (bandit) rules | clean; each `noqa` documents why | `api.yml` |
| axe (WCAG) + CSP-violation check in Playwright | clean | `web.yml` |
| Cross-tenant route generator + RLS tests | 151 backend tests run as a non-superuser role | `api.yml` |

## 4. Findings fixed in this review

1. **Shared client IP behind the BFF** — every web user reached the API from the BFF's address, so per-IP limits (and the new registration limit) would have been shared by everyone. Fixed with the authenticated client-IP header and proxy-hop-aware parsing (tests).
2. **Login brute force with rotating IPs** — limit keyed on email+IP only. Added a per-email limit.
3. **No security headers / caching rules on the API**; no CSP/HSTS on the web. Added (tests + Playwright check).
4. **No request body limit** — large JSON was parsed into memory before validation. 413 now, also for chunked bodies.
5. **Password in URL on JS failure** — forms defaulted to GET. All forms are POST.
6. **Mobile release builds could use plain HTTP.** Now rejected at startup (test).
7. **No database-level tenant isolation.** Row-level security on every tenant table (ADR-026).

## 5. Open / accepted

- ⏳ OIDC SSO and MFA (deferred by the product owner), ⏳ manual penetration test, ⏳ container image scanning (trivy) in CI, ⏳ edge rate limiting / WAF (platform feature), ⏳ secret rotation runbook.
- ⚠️ Email enumeration on registration (`auth.email_taken`): kept for usability; registration is rate-limited per IP.
- ⚠️ Local development connects as a Postgres superuser, which bypasses RLS; the API logs `rls_not_enforced` at startup in that case. Tests and staging use ordinary roles.

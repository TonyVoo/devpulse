#!/usr/bin/env bash
# Post-deploy smoke test. Usage: infra/scripts/smoke.sh API_URL WEB_URL [EXPECTED_RELEASE] [TIMEOUT_S]
# Waits until the API reports EXPECTED_RELEASE (if given) and is ready, then checks the web app.
set -euo pipefail
api="${1:?API_URL}"; web="${2:?WEB_URL}"; release="${3:-}"; timeout="${4:-900}"
deadline=$(( $(date +%s) + timeout ))

say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
until_ok() { # until_ok <description> <command...>
  local what="$1"; shift
  until "$@" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then say "FAILED: $what"; exit 1; fi
    sleep 10
  done
  say "ok: $what"
}

release_is() { curl -fsS --max-time 20 "$api/healthz" | grep -q "\"release\":\"$release\""; }
if [ -n "$release" ]; then until_ok "API runs release $release" release_is; fi
until_ok "API ready (database, Redis, migrations)" curl -fsS --max-time 20 "$api/readyz"

headers=$(curl -fsS --max-time 30 -D - -o /dev/null "$web/login")
echo "$headers" | grep -qi '^content-security-policy:.*nonce-' || { say "FAILED: web CSP header"; exit 1; }
echo "$headers" | grep -qi '^strict-transport-security:' || [[ "$web" != https://* ]] || { say "FAILED: HSTS"; exit 1; }
say "ok: web serves /login with a nonce CSP"

api_headers=$(curl -fsS --max-time 20 -D - -o /dev/null "$api/healthz")
echo "$api_headers" | grep -qi '^x-content-type-options: nosniff' || { say "FAILED: API security headers"; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$api/api/v1/me")
[ "$code" = "401" ] || { say "FAILED: /api/v1/me without a token returned $code (expected 401)"; exit 1; }
say "ok: API rejects unauthenticated requests"
say "smoke test passed"

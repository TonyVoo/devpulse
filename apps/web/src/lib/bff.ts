import "server-only";

import { cookies } from "next/headers";

import { backendFetch, refreshTokens, type BackendInit } from "./backend";
import {
  ACCESS_COOKIE,
  ACCESS_EXP_COOKIE,
  CSRF_COOKIE,
  CSRF_HEADER,
  REFRESH_COOKIE,
  accessTokenFresh,
  clearSession,
  writeSession,
} from "./session";

/** Paths whose responses contain tokens; they are handled by dedicated routes only. */
const BLOCKED_PREFIXES = ["auth/", "me/password"];

export function isBlockedPath(path: string): boolean {
  return BLOCKED_PREFIXES.some((p) => path === p.replace(/\/$/, "") || path.startsWith(p));
}

export function csrfValid(cookieValue: string | undefined, headerValue: string | null): boolean {
  if (!cookieValue || !headerValue || cookieValue.length !== headerValue.length) return false;
  let diff = 0;
  for (let i = 0; i < cookieValue.length; i++) {
    diff |= cookieValue.charCodeAt(i) ^ headerValue.charCodeAt(i);
  }
  return diff === 0;
}

export async function checkCsrf(request: Request): Promise<boolean> {
  const store = await cookies();
  return csrfValid(store.get(CSRF_COOKIE)?.value, request.headers.get(CSRF_HEADER));
}

/**
 * Call the API as the signed-in user (route handlers only — they may write cookies).
 * Refreshes proactively when the access token is near expiry, and once more on an
 * `auth.token_expired` 401. Returns null when there is no usable session.
 */
export async function authedFetch(path: string, init: BackendInit = {}): Promise<Response | null> {
  const store = await cookies();
  let access = store.get(ACCESS_COOKIE)?.value;
  const refresh = store.get(REFRESH_COOKIE)?.value;
  if (!refresh) return null;

  const doRefresh = async (): Promise<boolean> => {
    const tokens = await refreshTokens(refresh);
    if (!tokens) {
      clearSession(store);
      return false;
    }
    writeSession(store, tokens, store.get(CSRF_COOKIE)?.value);
    access = tokens.access_token;
    return true;
  };

  if (!access || !accessTokenFresh(store.get(ACCESS_EXP_COOKIE)?.value)) {
    if (!(await doRefresh())) return null;
  }
  let res = await backendFetch(path, { ...init, accessToken: access });
  if (res.status === 401) {
    const body = (await res.clone().json().catch(() => ({}))) as { code?: string };
    if (body.code === "auth.token_expired" || body.code === "auth.session_revoked") {
      if (!(await doRefresh())) return null;
      res = await backendFetch(path, { ...init, accessToken: access });
    }
  }
  return res;
}

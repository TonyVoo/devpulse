/**
 * BFF session cookies. Tokens live only in httpOnly cookies; browser JS never sees them.
 * Works with both `cookies()` (route handlers) and `NextResponse.cookies` (proxy).
 *
 * No `server-only` import: this module is also used by `proxy.ts`. It contains no secrets.
 */

export const ACCESS_COOKIE = "dp_at";
export const ACCESS_EXP_COOKIE = "dp_at_exp";
export const REFRESH_COOKIE = "dp_rt";
/** Double-submit CSRF token: readable by JS, echoed in the `x-csrf-token` header. */
export const CSRF_COOKIE = "dp_csrf";
export const CSRF_HEADER = "x-csrf-token";

/** Refresh the access token when it has less than this many seconds left. */
export const REFRESH_LEEWAY_S = 60;
const REFRESH_MAX_AGE_S = 60 * 60 * 24 * 30;

export type TokenPair = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  session_id: string;
};

type CookieOptions = {
  httpOnly?: boolean;
  secure?: boolean;
  sameSite?: "lax" | "strict" | "none";
  path?: string;
  maxAge?: number;
};

export interface CookieWriter {
  set(name: string, value: string, options?: CookieOptions): unknown;
}

function secure(): boolean {
  return process.env.SESSION_COOKIE_SECURE !== "false";
}

function base(maxAge: number, httpOnly = true): CookieOptions {
  return { httpOnly, secure: secure(), sameSite: "lax", path: "/", maxAge };
}

export function newCsrfToken(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function writeSession(store: CookieWriter, tokens: TokenPair, csrf?: string): void {
  const expAt = Math.floor(Date.now() / 1000) + tokens.expires_in;
  store.set(ACCESS_COOKIE, tokens.access_token, base(tokens.expires_in));
  store.set(ACCESS_EXP_COOKIE, String(expAt), base(tokens.expires_in));
  store.set(REFRESH_COOKIE, tokens.refresh_token, base(REFRESH_MAX_AGE_S));
  store.set(CSRF_COOKIE, csrf ?? newCsrfToken(), base(REFRESH_MAX_AGE_S, false));
}

export function clearSession(store: CookieWriter): void {
  for (const name of [ACCESS_COOKIE, ACCESS_EXP_COOKIE, REFRESH_COOKIE, CSRF_COOKIE]) {
    store.set(name, "", { ...base(0, name !== CSRF_COOKIE), maxAge: 0 });
  }
}

export function accessTokenFresh(expCookie: string | undefined, nowS = Date.now() / 1000): boolean {
  const exp = Number(expCookie ?? 0);
  return Number.isFinite(exp) && exp - nowS > REFRESH_LEEWAY_S;
}

/** Only allow same-origin relative redirects (prevents open redirects via `?next=`). */
export function safeNextPath(next: string | null | undefined, fallback = "/"): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) {
    return fallback;
  }
  return next;
}

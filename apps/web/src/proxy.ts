import { NextResponse, type NextRequest } from "next/server";

import { refreshTokens } from "@/lib/backend";
import { sentryOrigin } from "@/lib/sentry";
import {
  ACCESS_COOKIE,
  ACCESS_EXP_COOKIE,
  CSRF_COOKIE,
  REFRESH_COOKIE,
  accessTokenFresh,
  clearSession,
  writeSession,
} from "@/lib/session";

const PUBLIC_PATHS = ["/login", "/register"];

/**
 * Per-request Content-Security-Policy with a nonce. Next.js reads the nonce from the
 * request's CSP header and puts it on its own inline scripts; nothing else may run.
 * Styles allow inline (Tailwind/Recharts style attributes); no third-party origins.
 */
export function contentSecurityPolicy(
  nonce: string,
  dev = process.env.NODE_ENV === "development",
  sentry = sentryOrigin(),
): string {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${dev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    `connect-src 'self'${sentry ? ` ${sentry}` : ""}${dev ? " ws:" : ""}`,
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
}

function secure(request: NextRequest, res: NextResponse, csp: string): NextResponse {
  res.headers.set("Content-Security-Policy", csp);
  if (request.headers.get("x-forwarded-proto") === "https" || request.nextUrl.protocol === "https:") {
    res.headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  }
  return res;
}

/**
 * Page-request gate:
 *  - unauthenticated → /login?next=…
 *  - access token about to expire → refresh once here, so server components downstream
 *    see a valid token (forwarded on the request) and the browser gets new cookies.
 * API routes do their own refresh-on-401 (see app/api/v1/[...path]/route.ts).
 */
export async function proxy(request: NextRequest) {
  const nonce = btoa(crypto.randomUUID());
  const csp = contentSecurityPolicy(nonce);
  request.headers.set("Content-Security-Policy", csp);
  return secure(request, await gate(request), csp);
}

async function gate(request: NextRequest): Promise<NextResponse> {
  const { pathname, search } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));
  const refresh = request.cookies.get(REFRESH_COOKIE)?.value;
  // Forward the request headers (including the CSP nonce) to server components.
  const next = () => NextResponse.next({ request: { headers: request.headers } });

  if (!refresh) {
    if (isPublic) return next();
    const url = new URL("/login", request.url);
    if (pathname !== "/") url.searchParams.set("next", pathname + search);
    return NextResponse.redirect(url);
  }

  if (isPublic) return NextResponse.redirect(new URL("/", request.url));

  if (accessTokenFresh(request.cookies.get(ACCESS_EXP_COOKIE)?.value)) {
    return next();
  }

  let tokens = null;
  try {
    tokens = await refreshTokens(refresh);
  } catch {
    // API unreachable: let the page render and show its own error state rather than
    // logging the user out because of an outage.
    return next();
  }
  if (!tokens) {
    const res = NextResponse.redirect(new URL(`/login?next=${encodeURIComponent(pathname)}`, request.url));
    clearSession(res.cookies);
    return res;
  }

  // Make the new access token visible to this request's server components…
  request.cookies.set(ACCESS_COOKIE, tokens.access_token);
  const res = next();
  // …and persist the rotated tokens in the browser.
  writeSession(res.cookies, tokens, request.cookies.get(CSRF_COOKIE)?.value);
  return res;
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|.*\\..*).*)"],
};

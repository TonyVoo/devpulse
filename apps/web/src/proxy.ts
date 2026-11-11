import { NextResponse, type NextRequest } from "next/server";

import { refreshTokens } from "@/lib/backend";
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
 * Page-request gate:
 *  - unauthenticated → /login?next=…
 *  - access token about to expire → refresh once here, so server components downstream
 *    see a valid token (forwarded on the request) and the browser gets new cookies.
 * API routes do their own refresh-on-401 (see app/api/v1/[...path]/route.ts).
 */
export async function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));
  const refresh = request.cookies.get(REFRESH_COOKIE)?.value;

  if (!refresh) {
    if (isPublic) return NextResponse.next();
    const url = new URL("/login", request.url);
    if (pathname !== "/") url.searchParams.set("next", pathname + search);
    return NextResponse.redirect(url);
  }

  if (isPublic) return NextResponse.redirect(new URL("/", request.url));

  if (accessTokenFresh(request.cookies.get(ACCESS_EXP_COOKIE)?.value)) {
    return NextResponse.next();
  }

  let tokens = null;
  try {
    tokens = await refreshTokens(refresh);
  } catch {
    // API unreachable: let the page render and show its own error state rather than
    // logging the user out because of an outage.
    return NextResponse.next();
  }
  if (!tokens) {
    const res = NextResponse.redirect(new URL(`/login?next=${encodeURIComponent(pathname)}`, request.url));
    clearSession(res.cookies);
    return res;
  }

  // Make the new access token visible to this request's server components…
  request.cookies.set(ACCESS_COOKIE, tokens.access_token);
  const res = NextResponse.next({ request: { headers: request.headers } });
  // …and persist the rotated tokens in the browser.
  writeSession(res.cookies, tokens, request.cookies.get(CSRF_COOKIE)?.value);
  return res;
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|.*\\..*).*)"],
};

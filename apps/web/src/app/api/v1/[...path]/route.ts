/**
 * Generic BFF proxy for client-side data fetching: /api/v1/<path> → API /api/v1/<path>,
 * authenticated with the httpOnly session. Token-bearing endpoints are not reachable here.
 */
import { passThrough, problemResponse } from "@/lib/backend";
import { authedFetch, checkCsrf, isBlockedPath } from "@/lib/bff";

const MAX_BODY_BYTES = 1_000_000;

async function handle(request: Request, ctx: RouteContext<"/api/v1/[...path]">) {
  const { path: segments } = await ctx.params;
  const path = segments.map(encodeURIComponent).join("/");
  if (isBlockedPath(path)) return problemResponse(404, "not_found", "Not found");

  const method = request.method.toUpperCase();
  const mutating = method !== "GET" && method !== "HEAD";
  if (mutating && !(await checkCsrf(request))) {
    return problemResponse(403, "csrf.invalid", "Missing or invalid CSRF token");
  }

  let body: string | undefined;
  if (mutating) {
    body = await request.text();
    if (body.length > MAX_BODY_BYTES) {
      return problemResponse(413, "payload_too_large", "Request body too large");
    }
  }
  const search = new URL(request.url).search;
  const headers: Record<string, string> = {};
  for (const name of ["content-type", "if-match", "idempotency-key", "x-request-id"]) {
    const v = request.headers.get(name);
    if (v) headers[name] = v;
  }

  let upstream: Response | null;
  try {
    upstream = await authedFetch(`${path}${search}`, { method, body: body || undefined, headers });
  } catch {
    return problemResponse(503, "api_unavailable", "The DevPulse API is unreachable");
  }
  if (!upstream) return problemResponse(401, "auth.unauthorized", "Sign in required");
  return passThrough(upstream);
}

export { handle as GET, handle as POST, handle as PUT, handle as PATCH, handle as DELETE };

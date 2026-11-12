import "server-only";

import { cookies } from "next/headers";

import { backendFetch, clientIpFrom, passThrough, problemResponse } from "./backend";
import { writeSession, type TokenPair } from "./session";

/**
 * Shared handler for login/register: forwards credentials to the API, stores the returned
 * tokens in httpOnly cookies and returns only the user profile to the browser.
 *
 * CSRF: requires `application/json`, which cross-site HTML forms cannot send without a CORS
 * preflight (and the API has no CORS for this origin). Cookies are SameSite=Lax as well.
 */
export async function credentialExchange(request: Request, apiPath: string): Promise<Response> {
  if (!request.headers.get("content-type")?.startsWith("application/json")) {
    return problemResponse(415, "unsupported_media_type", "Expected application/json");
  }
  let upstream: Response;
  try {
    upstream = await backendFetch(apiPath, {
      method: "POST",
      body: await request.text(),
      clientIp: clientIpFrom(request.headers),
    });
  } catch {
    return problemResponse(503, "api_unavailable", "The DevPulse API is unreachable");
  }
  if (!upstream.ok) return passThrough(upstream);

  const body = (await upstream.json()) as TokenPair & { user: unknown };
  writeSession(await cookies(), body);
  return Response.json({ user: body.user }, { status: upstream.status });
}

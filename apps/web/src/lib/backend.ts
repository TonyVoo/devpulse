/**
 * Server-side calls from the BFF to the DevPulse API. Used by route handlers, server
 * components and `proxy.ts`. Never import from client components.
 */
import type { TokenPair } from "./session";

export type Problem = {
  type?: string;
  title: string;
  status: number;
  detail: string;
  code: string;
  request_id?: string | null;
  errors?: { loc: (string | number)[]; msg: string; type: string }[];
};

export function apiBaseUrl(): string {
  const url = process.env.API_INTERNAL_URL;
  if (!url) throw new Error("API_INTERNAL_URL is not configured");
  return url.replace(/\/+$/, "");
}

/**
 * The browser's IP as seen by this server. Behind N trusted proxies (TRUSTED_PROXY_HOPS,
 * Render: 1) it is the Nth X-Forwarded-For entry from the right; entries further left are
 * client-supplied and ignored. Undefined when unknown (the API then sees this server's IP).
 */
export function clientIpFrom(headers: Headers, hops = Number(process.env.TRUSTED_PROXY_HOPS ?? 0)): string | undefined {
  if (!hops) return undefined;
  const chain = (headers.get("x-forwarded-for") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return chain.length >= hops ? chain[chain.length - hops] : undefined;
}

export type BackendInit = RequestInit & { accessToken?: string; clientIp?: string };

export async function backendFetch(path: string, init: BackendInit = {}): Promise<Response> {
  const { accessToken, clientIp, headers, ...rest } = init;
  const h = new Headers(headers);
  if (accessToken) h.set("authorization", `Bearer ${accessToken}`);
  // The API trusts this header only together with the shared secret (rate limits per IP).
  const secret = process.env.BFF_SHARED_SECRET;
  if (clientIp && secret) {
    h.set("x-devpulse-client-ip", clientIp);
    h.set("x-devpulse-bff-secret", secret);
  }
  if (rest.body && !h.has("content-type")) h.set("content-type", "application/json");
  h.set("accept", "application/json");
  return fetch(`${apiBaseUrl()}/api/v1/${path.replace(/^\/+/, "")}`, {
    ...rest,
    headers: h,
    cache: "no-store",
    signal: rest.signal ?? AbortSignal.timeout(15_000),
  });
}

/** Returns new tokens, or null when the refresh token is no longer valid. */
export async function refreshTokens(refreshToken: string): Promise<TokenPair | null> {
  const r = await backendFetch("auth/refresh", {
    method: "POST",
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (r.status === 401) return null;
  if (!r.ok) throw new Error(`refresh failed with ${r.status}`);
  return (await r.json()) as TokenPair;
}

export function problemResponse(
  status: number,
  code: string,
  detail: string,
  title = detail,
): Response {
  const body: Problem = { title, status, detail, code };
  return Response.json(body, {
    status,
    headers: { "content-type": "application/problem+json" },
  });
}

/** Copy an upstream response through, keeping only safe headers. */
export async function passThrough(upstream: Response): Promise<Response> {
  const headers = new Headers();
  for (const name of ["content-type", "x-request-id", "retry-after", "etag"]) {
    const v = upstream.headers.get(name);
    if (v) headers.set(name, v);
  }
  const body = upstream.status === 204 ? null : await upstream.arrayBuffer();
  return new Response(body, { status: upstream.status, headers });
}

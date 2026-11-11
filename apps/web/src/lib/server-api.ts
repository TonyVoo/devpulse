import "server-only";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import type { components } from "./api-types";
import { backendFetch } from "./backend";
import { ACCESS_COOKIE } from "./session";

export type Me = components["schemas"]["MeOut"];

export class BackendUnavailableError extends Error {}

/**
 * Data access for Server Components. `proxy.ts` has already refreshed the access token
 * for this request, so a 401 here means the session is gone.
 */
export async function serverGet<T>(path: string): Promise<T> {
  const access = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!access) redirect("/login");
  let res: Response;
  try {
    res = await backendFetch(path, { accessToken: access });
  } catch (e) {
    throw new BackendUnavailableError(`API unreachable: ${(e as Error).message}`);
  }
  if (res.status === 401) redirect("/login");
  if (!res.ok) throw new Error(`GET ${path} failed with ${res.status}`);
  return (await res.json()) as T;
}

export function getMe(): Promise<Me> {
  return serverGet<Me>("me");
}

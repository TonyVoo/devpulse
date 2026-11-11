import { cookies } from "next/headers";

import { backendFetch, problemResponse } from "@/lib/backend";
import { checkCsrf } from "@/lib/bff";
import { ACCESS_COOKIE, clearSession } from "@/lib/session";

export async function POST(request: Request) {
  if (!(await checkCsrf(request))) {
    return problemResponse(403, "csrf.invalid", "Missing or invalid CSRF token");
  }
  const store = await cookies();
  const access = store.get(ACCESS_COOKIE)?.value;
  if (access) {
    // Best effort: revoke server-side. Local cookies are cleared regardless.
    await backendFetch("auth/logout", { method: "POST", accessToken: access }).catch(() => null);
  }
  clearSession(store);
  return new Response(null, { status: 204 });
}

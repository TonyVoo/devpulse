import "server-only";

import { cookies, headers } from "next/headers";

import { LOCALE_COOKIE, resolveLocale, type Locale } from "./config";
import { makeT, type T } from "./translate";

/** Language for this request: saved choice, else the browser's Accept-Language. */
export async function getLocale(): Promise<Locale> {
  const [c, h] = await Promise.all([cookies(), headers()]);
  return resolveLocale(c.get(LOCALE_COOKIE)?.value, h.get("accept-language"));
}

export async function getT(): Promise<T> {
  return makeT(await getLocale());
}

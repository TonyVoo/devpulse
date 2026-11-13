import { INTL_LOCALE, type Locale } from "./config";
import { en, type Messages } from "./messages/en";
import { vi } from "./messages/vi";

const DICTS: Record<Locale, Messages> = { en, vi };

/** "a.b.c" paths to every string in the dictionary, checked at compile time. */
type Paths<T, P extends string = ""> = {
  [K in keyof T & string]: T[K] extends string ? `${P}${K}` : Paths<T[K], `${P}${K}.`>;
}[keyof T & string];

export type MessageKey = Paths<Messages>;
export type Vars = Record<string, string | number>;
export type T = (key: MessageKey, vars?: Vars) => string;

/** Walks "a.b.c"; a key may itself contain dots (API codes such as "auth.email_taken"). */
function walk(node: unknown, parts: string[]): string | undefined {
  if (parts.length === 0) return typeof node === "string" ? node : undefined;
  if (node === null || typeof node !== "object") return undefined;
  for (let i = parts.length; i >= 1; i--) {
    const k = parts.slice(0, i).join(".");
    if (k in node) {
      const hit = walk((node as Record<string, unknown>)[k], parts.slice(i));
      if (hit !== undefined) return hit;
    }
  }
  return undefined;
}

function lookup(dict: Messages, key: string): string | undefined {
  return walk(dict, key.split("."));
}

/** True when `key` names a message (for keys built at runtime, e.g. from API error codes). */
export function hasMessage(key: string): key is MessageKey {
  return lookup(en, key) !== undefined;
}

/** Translate `key` into `locale`, filling `{name}` placeholders. Falls back to English. */
export function translate(locale: Locale, key: MessageKey, vars?: Vars): string {
  const raw = lookup(DICTS[locale], key) ?? lookup(en, key) ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (m, name: string) => (name in vars ? String(vars[name]) : m));
}

/** `t(key)` for keys built from API values; unknown values are shown as they are. */
export function tOr(t: T, key: string, fallback: string): string {
  return hasMessage(key) ? t(key) : fallback;
}

export function makeT(locale: Locale): T {
  return (key, vars) => translate(locale, key, vars);
}

/** Relative time in the given language ("5m ago" / "5 phút trước"). */
export function timeAgo(iso: string | null | undefined, now = Date.now(), locale: Locale = "en"): string {
  const t = makeT(locale);
  if (!iso) return t("time.never");
  const s = Math.max(0, (now - new Date(iso).getTime()) / 1000);
  if (s < 60) return t("time.justNow");
  if (s < 3600) return t("time.minutesAgo", { n: Math.floor(s / 60) });
  if (s < 86400) return t("time.hoursAgo", { n: Math.floor(s / 3600) });
  return t("time.daysAgo", { n: Math.floor(s / 86400) });
}

/** Number formatters for metrics, with the locale's decimal separator. */
export function makeFmt(locale: Locale) {
  const tag = INTL_LOCALE[locale];
  const nf = (digits: number) =>
    new Intl.NumberFormat(tag, { minimumFractionDigits: digits, maximumFractionDigits: digits, useGrouping: false });
  const n0 = nf(0);
  const n1 = nf(1);
  const n2 = nf(2);
  return {
    ms: (v: number) => (v >= 1000 ? `${n2.format(v / 1000)} s` : `${n0.format(Math.round(v))} ms`),
    pct: (v: number) => `${(v < 0.01 ? n2 : n1).format(v * 100)}%`,
    count: (v: number) => (v >= 1000 ? `${n1.format(v / 1000)}k` : n0.format(Math.round(v))),
    num: (v: number) => (Math.abs(v) >= 100 ? n0 : n2).format(v),
    /** Grouped integer, e.g. 12,345 / 12.345. */
    int: (v: number) => new Intl.NumberFormat(tag).format(v),
  };
}
export type Fmt = ReturnType<typeof makeFmt>;

export function formatDate(iso: string | number, locale: Locale, opts: Intl.DateTimeFormatOptions): string {
  return new Date(iso).toLocaleString(INTL_LOCALE[locale], opts);
}

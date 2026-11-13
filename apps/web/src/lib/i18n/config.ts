/** Languages the web app ships. English is the source language and the fallback. */
export const LOCALES = ["en", "vi"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

/** Preference cookie (not a secret: readable by scripts, sent with page requests). */
export const LOCALE_COOKIE = "dp_locale";
export const LOCALE_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

/** BCP 47 tags for Intl formatting. */
export const INTL_LOCALE: Record<Locale, string> = { en: "en-US", vi: "vi-VN" };

/** Names shown in the language switcher, each in its own language. */
export const LOCALE_NAME: Record<Locale, string> = { en: "English", vi: "Tiếng Việt" };

export function isLocale(v: unknown): v is Locale {
  return typeof v === "string" && (LOCALES as readonly string[]).includes(v);
}

/** Saved choice first, then the browser's preferred languages, then English. */
export function resolveLocale(cookie: string | undefined | null, acceptLanguage: string | undefined | null): Locale {
  if (isLocale(cookie)) return cookie;
  const ranked = (acceptLanguage ?? "")
    .split(",")
    .map((part) => {
      const [tag, ...params] = part.trim().toLowerCase().split(";");
      const q = params.find((p) => p.trim().startsWith("q="));
      return { lang: tag.split("-")[0], q: q ? Number(q.trim().slice(2)) || 0 : 1 };
    })
    .filter((x) => x.lang)
    .sort((a, b) => b.q - a.q);
  return ranked.map((x) => x.lang).find(isLocale) ?? DEFAULT_LOCALE;
}

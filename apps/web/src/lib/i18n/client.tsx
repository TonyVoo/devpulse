"use client";

import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useMemo, type ReactNode } from "react";

import { LOCALE_COOKIE, LOCALE_COOKIE_MAX_AGE, type Locale } from "./config";
import { formatDate, makeFmt, makeT, timeAgo, type Fmt, type T } from "./translate";

type I18n = {
  locale: Locale;
  t: T;
  fmt: Fmt;
  /** Relative time ("5m ago") in the current language. */
  ago: (iso: string | null | undefined) => string;
  /** Absolute date/time in the current language. */
  date: (iso: string | number, opts?: Intl.DateTimeFormatOptions) => string;
};

function build(locale: Locale): I18n {
  return {
    locale,
    t: makeT(locale),
    fmt: makeFmt(locale),
    ago: (iso) => timeAgo(iso, Date.now(), locale),
    date: (iso, opts = { dateStyle: "medium", timeStyle: "short" }) => formatDate(iso, locale, opts),
  };
}

// Components rendered outside the provider (unit tests) get English.
const Ctx = createContext<I18n>(build("en"));

export function I18nProvider({ locale, children }: { locale: Locale; children: ReactNode }) {
  const value = useMemo(() => build(locale), [locale]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  return useContext(Ctx);
}

/** Saves the choice in a cookie and re-renders server components in the new language. */
export function useSetLocale(): (locale: Locale) => void {
  const router = useRouter();
  return useCallback(
    (locale: Locale) => {
      const secure = window.location.protocol === "https:" ? "; Secure" : "";
      document.cookie = `${LOCALE_COOKIE}=${locale}; Path=/; Max-Age=${LOCALE_COOKIE_MAX_AGE}; SameSite=Lax${secure}`;
      document.documentElement.lang = locale;
      router.refresh();
    },
    [router],
  );
}

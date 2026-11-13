"use client";

import { LOCALE_NAME, LOCALES } from "@/lib/i18n/config";
import { useI18n, useSetLocale } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";

/**
 * EN | VI toggle. Each option is named in its own language for screen readers.
 * `compact` (phone header): one button that shows and switches to the other language.
 */
export function LanguageSwitcher({ className, compact = false }: { className?: string; compact?: boolean }) {
  const { locale, t } = useI18n();
  const setLocale = useSetLocale();
  if (compact) {
    const other = LOCALES.find((l) => l !== locale)!;
    return (
      <button
        type="button"
        onClick={() => setLocale(other)}
        aria-label={t("common.switchTo", { language: LOCALE_NAME[other] })}
        title={LOCALE_NAME[other]}
        lang={other}
        className={cn(
          "min-h-9 shrink-0 rounded-md border border-line px-2 text-xs font-semibold uppercase tracking-wide text-fg-muted hover:text-fg",
          className,
        )}
      >
        {other}
      </button>
    );
  }
  return (
    <div
      role="radiogroup"
      aria-label={t("common.language")}
      className={cn("inline-flex shrink-0 rounded-md border border-line p-0.5 text-xs", className)}
    >
      {LOCALES.map((l) => (
        <button
          key={l}
          type="button"
          role="radio"
          aria-checked={l === locale}
          aria-label={LOCALE_NAME[l]}
          lang={l}
          title={LOCALE_NAME[l]}
          onClick={() => l !== locale && setLocale(l)}
          className={cn(
            "min-h-7 min-w-9 rounded px-2 font-semibold uppercase tracking-wide transition-colors",
            l === locale ? "bg-raised text-fg" : "text-fg-subtle hover:text-fg",
          )}
        >
          {l}
        </button>
      ))}
    </div>
  );
}

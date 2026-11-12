import type { Instrumentation } from "next";

import { NO_PERSONAL_DATA, scrubEvent } from "@/lib/sentry";

/** Server-side error reporting (Node runtime). Off unless SENTRY_DSN is set. */
export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs" || !process.env.SENTRY_DSN) return;
  const Sentry = await import("@sentry/nextjs");
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.APP_ENV ?? "local",
    release: process.env.RELEASE || undefined,
    dataCollection: NO_PERSONAL_DATA,
    tracesSampleRate: 0,
    beforeSend: (event) => scrubEvent(event),
  });
}

export const onRequestError: Instrumentation.onRequestError = async (...args) => {
  if (!process.env.SENTRY_DSN) return;
  const Sentry = await import("@sentry/nextjs");
  Sentry.captureRequestError(...args);
};

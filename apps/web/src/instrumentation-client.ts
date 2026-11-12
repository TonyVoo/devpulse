import { NO_PERSONAL_DATA, scrubEvent } from "@/lib/sentry";

// Browser error reporting. NEXT_PUBLIC_SENTRY_DSN is inlined at build time; without it the
// SDK is never loaded.
if (process.env.NEXT_PUBLIC_SENTRY_DSN) {
  void import("@sentry/nextjs").then((Sentry) =>
    Sentry.init({
      dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
      environment: process.env.NEXT_PUBLIC_APP_ENV ?? "local",
      dataCollection: NO_PERSONAL_DATA,
      tracesSampleRate: 0,
      beforeSend: (event) => scrubEvent(event),
    }),
  );
}

/** Shared Sentry options for the web app. Error reporting is off unless a DSN is set. */

/** Collect no user info, cookies, headers, bodies or query strings (v11 `dataCollection`). */
export const NO_PERSONAL_DATA = {
  userInfo: false,
  cookies: false,
  httpHeaders: false,
  httpBodies: [],
  urlQueryParams: false,
};
type SentryEvent = {
  request?: { cookies?: unknown; data?: unknown; headers?: { [key: string]: string } };
  user?: unknown;
};

/** Strip anything that could carry credentials or personal data before an event leaves. */
export function scrubEvent<T extends SentryEvent>(event: T): T {
  if (event.request) {
    delete event.request.cookies;
    delete event.request.data;
    const headers = event.request.headers;
    if (headers) {
      for (const k of Object.keys(headers)) {
        if (/^(authorization|cookie|x-csrf-token|x-devpulse-bff-secret)$/i.test(k)) headers[k] = "[Filtered]";
      }
    }
  }
  delete event.user;
  return event;
}

/** Origin of the Sentry ingest host for the CSP (undefined when Sentry is off). */
export function sentryOrigin(dsn = process.env.NEXT_PUBLIC_SENTRY_DSN): string | undefined {
  if (!dsn) return undefined;
  try {
    return new URL(dsn).origin;
  } catch {
    return undefined;
  }
}

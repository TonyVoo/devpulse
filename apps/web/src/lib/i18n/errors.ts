import { ApiError } from "@/lib/api-client";

import { hasMessage, type T } from "./translate";

/**
 * Text for a failed request: a translated message for known API error codes, otherwise the
 * API's own (English) detail, so nothing useful is hidden.
 */
export function errorText(error: unknown, t: T): string {
  if (error instanceof ApiError) {
    const code = error.problem.code;
    const key = code ? `errors.${code}` : "";
    if (code && hasMessage(key)) return t(key);
    if (error.status === 429) return t("errors.rate_limited");
    if (error.status === 0 || error.status === 503) return t("errors.api_unavailable");
    return error.problem.errors?.[0]?.msg ?? error.problem.detail ?? error.message;
  }
  return t("common.somethingWrong");
}

/** Browser-side API client. Talks only to the same-origin BFF (`/api/v1/*`). */
import { CSRF_COOKIE, CSRF_HEADER } from "./session";

export type ProblemBody = {
  title: string;
  status: number;
  detail: string;
  code: string;
  request_id?: string | null;
  errors?: { loc: (string | number)[]; msg: string }[];
};

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly problem: ProblemBody,
  ) {
    super(problem.detail || problem.title);
  }
}

export function readCookie(name: string): string | undefined {
  if (typeof document === "undefined") return undefined;
  return document.cookie
    .split("; ")
    .find((c) => c.startsWith(`${name}=`))
    ?.slice(name.length + 1);
}

async function toError(res: Response): Promise<ApiError> {
  const fallback: ProblemBody = {
    title: res.statusText || "Request failed",
    status: res.status,
    detail: "Something went wrong. Please try again.",
    code: "http_error",
  };
  const body = (await res.json().catch(() => null)) as ProblemBody | null;
  return new ApiError(res.status, body && body.code ? body : fallback);
}

export async function request<T>(
  url: string,
  init: RequestInit & { json?: unknown } = {},
): Promise<T> {
  const { json, headers, ...rest } = init;
  const h = new Headers(headers);
  if (json !== undefined) h.set("content-type", "application/json");
  const csrf = readCookie(CSRF_COOKIE);
  if (csrf) h.set(CSRF_HEADER, csrf);
  let res: Response;
  try {
    res = await fetch(url, {
      ...rest,
      headers: h,
      body: json !== undefined ? JSON.stringify(json) : rest.body,
      credentials: "same-origin",
    });
  } catch {
    throw new ApiError(0, {
      title: "Network error",
      status: 0,
      detail: "Can't reach DevPulse. Check your connection.",
      code: "network",
    });
  }
  if (!res.ok) throw await toError(res);
  return (res.status === 204 ? undefined : await res.json()) as T;
}

export const api = {
  get: <T>(path: string) => request<T>(`/api/v1/${path}`),
  post: <T>(path: string, json?: unknown) => request<T>(`/api/v1/${path}`, { method: "POST", json }),
  patch: <T>(path: string, json?: unknown) => request<T>(`/api/v1/${path}`, { method: "PATCH", json }),
  put: <T>(path: string, json?: unknown) => request<T>(`/api/v1/${path}`, { method: "PUT", json }),
  delete: <T>(path: string) => request<T>(`/api/v1/${path}`, { method: "DELETE" }),
};

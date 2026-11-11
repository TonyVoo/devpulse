import { describe, expect, it } from "vitest";

import {
  ACCESS_COOKIE,
  CSRF_COOKIE,
  REFRESH_COOKIE,
  accessTokenFresh,
  clearSession,
  safeNextPath,
  writeSession,
  type CookieWriter,
} from "./session";

function recorder() {
  const calls: Record<string, { value: string; options?: Record<string, unknown> }> = {};
  const store: CookieWriter = {
    set: (name, value, options) => {
      calls[name] = { value, options };
    },
  };
  return { store, calls };
}

describe("safeNextPath", () => {
  it.each([
    ["/o/123/members", "/o/123/members"],
    ["//evil.example", "/"],
    ["/\\evil.example", "/"],
    ["https://evil.example", "/"],
    [undefined, "/"],
  ])("%s → %s", (input, expected) => {
    expect(safeNextPath(input)).toBe(expected);
  });
});

describe("accessTokenFresh", () => {
  it("treats tokens inside the refresh leeway as stale", () => {
    const now = 1_000_000;
    expect(accessTokenFresh(String(now + 600), now)).toBe(true);
    expect(accessTokenFresh(String(now + 30), now)).toBe(false);
    expect(accessTokenFresh(undefined, now)).toBe(false);
    expect(accessTokenFresh("garbage", now)).toBe(false);
  });
});

describe("writeSession / clearSession", () => {
  const tokens = { access_token: "a", refresh_token: "r", expires_in: 900, session_id: "s" };

  it("stores tokens httpOnly and the CSRF token readable", () => {
    const { store, calls } = recorder();
    writeSession(store, tokens);
    expect(calls[ACCESS_COOKIE].options).toMatchObject({ httpOnly: true, sameSite: "lax", path: "/" });
    expect(calls[REFRESH_COOKIE].options).toMatchObject({ httpOnly: true });
    expect(calls[CSRF_COOKIE].options).toMatchObject({ httpOnly: false });
    expect(calls[CSRF_COOKIE].value).toMatch(/^[0-9a-f]{48}$/);
  });

  it("keeps an existing CSRF token across refreshes", () => {
    const { store, calls } = recorder();
    writeSession(store, tokens, "existing");
    expect(calls[CSRF_COOKIE].value).toBe("existing");
  });

  it("expires every session cookie on clear", () => {
    const { store, calls } = recorder();
    clearSession(store);
    expect(Object.values(calls).every((c) => c.options?.maxAge === 0 && c.value === "")).toBe(true);
    expect(Object.keys(calls)).toHaveLength(4);
  });
});

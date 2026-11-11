import { describe, expect, it, vi } from "vitest";

vi.mock("next/headers", () => ({ cookies: vi.fn() }));

import { csrfValid, isBlockedPath } from "./bff";

describe("isBlockedPath", () => {
  it("blocks endpoints whose responses carry tokens", () => {
    expect(isBlockedPath("auth/refresh")).toBe(true);
    expect(isBlockedPath("auth/login")).toBe(true);
    expect(isBlockedPath("me/password")).toBe(true);
  });

  it("allows regular resources", () => {
    expect(isBlockedPath("me")).toBe(false);
    expect(isBlockedPath("orgs/123/members")).toBe(false);
    expect(isBlockedPath("me/sessions")).toBe(false);
  });
});

describe("csrfValid", () => {
  it("requires an exact match", () => {
    expect(csrfValid("abc123", "abc123")).toBe(true);
    expect(csrfValid("abc123", "abc124")).toBe(false);
    expect(csrfValid("abc123", null)).toBe(false);
    expect(csrfValid(undefined, "abc123")).toBe(false);
    expect(csrfValid("abc", "abc123")).toBe(false);
  });
});

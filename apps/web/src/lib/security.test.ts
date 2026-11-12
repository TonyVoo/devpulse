import { render } from "@testing-library/react";
import { createElement } from "react";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ replace: vi.fn(), refresh: vi.fn() }) }));
vi.mock("@/lib/backend", () => ({ refreshTokens: vi.fn() }));

import { AuthForm } from "@/components/auth/auth-form";
import { contentSecurityPolicy } from "@/proxy";

describe("security", () => {
  it("builds a nonce CSP with no third-party origins and no eval in production", () => {
    const csp = contentSecurityPolicy("abc123", false);
    expect(csp).toContain("script-src 'self' 'nonce-abc123' 'strict-dynamic'");
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toMatch(/https?:\/\//);
    expect(contentSecurityPolicy("x", true)).toContain("'unsafe-eval'"); // dev server only
    expect(contentSecurityPolicy("x", false, "https://o1.ingest.sentry.io")).toContain(
      "connect-src 'self' https://o1.ingest.sentry.io",
    );
  });

  it("scrubs credentials from error reports", async () => {
    const { scrubEvent, sentryOrigin } = await import("@/lib/sentry");
    const e = scrubEvent({
      request: { headers: { Authorization: "Bearer x", "X-CSRF-Token": "t", Accept: "json" }, cookies: { a: "b" }, data: "pw" },
      user: { email: "a@b.c" },
    });
    expect(e.request?.headers).toEqual({ Authorization: "[Filtered]", "X-CSRF-Token": "[Filtered]", Accept: "json" });
    expect(e.request?.cookies).toBeUndefined();
    expect(e.user).toBeUndefined();
    expect(sentryOrigin("https://key@o1.ingest.sentry.io/42")).toBe("https://o1.ingest.sentry.io");
    expect(sentryOrigin(undefined)).toBeUndefined();
  });

  it("auth forms never fall back to GET (the password would land in the URL)", () => {
    const { container } = render(createElement(AuthForm, { mode: "login" }));
    expect(container.querySelector("form")?.getAttribute("method")).toBe("post");
  });
});

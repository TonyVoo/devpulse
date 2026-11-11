import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/lib/api-client";

const replace = vi.fn();
const refresh = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ replace, refresh }) }));

import { AuthForm, describeError } from "./auth-form";

function problem(status: number, code: string, detail: string, errors?: unknown[]) {
  return new Response(JSON.stringify({ status, code, detail, title: detail, errors }), {
    status,
    headers: { "content-type": "application/problem+json" },
  });
}

beforeEach(() => {
  replace.mockReset();
  refresh.mockReset();
});
afterEach(() => vi.unstubAllGlobals());

describe("AuthForm", () => {
  it("signs in and navigates to a safe `next` path", async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ user: { id: "u" } }));
    vi.stubGlobal("fetch", fetchMock);
    render(<AuthForm mode="login" next="/o/42/members" />);

    await userEvent.type(screen.getByLabelText("Work email"), "ada@example.com");
    await userEvent.type(screen.getByLabelText("Password"), "correct-horse-battery");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/auth/login",
      expect.objectContaining({ method: "POST" }),
    );
    const body = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(body).toEqual({ email: "ada@example.com", password: "correct-horse-battery" });
    expect(replace).toHaveBeenCalledWith("/o/42/members");
  });

  it("ignores an off-site `next` parameter", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ user: {} })));
    render(<AuthForm mode="login" next="//evil.example" />);
    await userEvent.type(screen.getByLabelText("Work email"), "a@b.co");
    await userEvent.type(screen.getByLabelText("Password"), "x");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(replace).toHaveBeenCalledWith("/");
  });

  it("shows the API's error and stays on the page", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(problem(401, "auth.invalid_credentials", "Email or password is incorrect")),
    );
    render(<AuthForm mode="login" />);
    await userEvent.type(screen.getByLabelText("Work email"), "a@b.co");
    await userEvent.type(screen.getByLabelText("Password"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Email or password is incorrect");
    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Sign in" })).toBeEnabled();
  });

  it("marks invalid fields on registration", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        problem(422, "validation.failed", "invalid", [
          { loc: ["body", "password"], msg: "String should have at least 12 characters", type: "x" },
        ]),
      ),
    );
    render(<AuthForm mode="register" />);
    await userEvent.type(screen.getByLabelText("Name"), "Ada");
    await userEvent.type(screen.getByLabelText("Work email"), "ada@example.com");
    await userEvent.type(screen.getByLabelText("Password"), "short");
    await userEvent.click(screen.getByRole("button", { name: "Create account" }));

    expect(await screen.findByText("Use at least 12 characters.")).toBeInTheDocument();
    expect(screen.getByLabelText("Password")).toHaveAttribute("aria-invalid", "true");
  });
});

describe("describeError", () => {
  it("explains rate limiting in plain words", () => {
    const err = new ApiError(429, { status: 429, code: "rate_limited", title: "", detail: "Too many" });
    expect(describeError(err).message).toMatch(/Too many attempts/);
  });

  it("falls back for unknown errors", () => {
    expect(describeError(new Error("boom")).message).toBe("Something went wrong. Try again.");
  });
});

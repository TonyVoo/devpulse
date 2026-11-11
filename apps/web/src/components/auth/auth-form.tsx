"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { ApiError, request } from "@/lib/api-client";
import { safeNextPath } from "@/lib/session";

type Mode = "login" | "register";

const COPY: Record<Mode, { title: string; submit: string; switchText: string; switchHref: string; switchCta: string }> = {
  login: {
    title: "Sign in to DevPulse",
    submit: "Sign in",
    switchText: "New to DevPulse?",
    switchHref: "/register",
    switchCta: "Create an account",
  },
  register: {
    title: "Create your account",
    submit: "Create account",
    switchText: "Already have an account?",
    switchHref: "/login",
    switchCta: "Sign in",
  },
};

/** Maps API problem responses to a form-level message plus per-field messages. */
export function describeError(error: unknown): { message: string; fields: Record<string, string> } {
  if (!(error instanceof ApiError)) return { message: "Something went wrong. Try again.", fields: {} };
  const fields: Record<string, string> = {};
  for (const e of error.problem.errors ?? []) {
    const key = String(e.loc[e.loc.length - 1]);
    fields[key] =
      key === "password" && e.msg.includes("at least")
        ? "Use at least 12 characters."
        : key === "email"
          ? "Enter a valid email address."
          : e.msg;
  }
  const message =
    error.status === 429
      ? "Too many attempts. Wait a few minutes and try again."
      : error.problem.code === "validation.failed"
        ? "Check the highlighted fields."
        : error.problem.detail;
  return { message, fields };
}

export function AuthForm({ mode, next }: { mode: Mode; next?: string }) {
  const router = useRouter();
  const copy = COPY[mode];
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<{ message: string; fields: Record<string, string> } | null>(null);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.currentTarget));
    setPending(true);
    setError(null);
    try {
      await request(`/api/auth/${mode}`, { method: "POST", json: data });
      router.replace(safeNextPath(next));
      router.refresh();
    } catch (e) {
      setError(describeError(e));
      setPending(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      <h1 className="text-xl font-semibold">{copy.title}</h1>
      {error && <Alert>{error.message}</Alert>}
      {mode === "register" && (
        <Field
          label="Name"
          name="display_name"
          autoComplete="name"
          required
          error={error?.fields.display_name}
        />
      )}
      <Field
        label="Work email"
        name="email"
        type="email"
        autoComplete="email"
        required
        error={error?.fields.email}
      />
      <Field
        label="Password"
        name="password"
        type="password"
        autoComplete={mode === "login" ? "current-password" : "new-password"}
        hint={mode === "register" ? "At least 12 characters." : undefined}
        required
        error={error?.fields.password}
      />
      <Button type="submit" loading={pending}>
        {copy.submit}
      </Button>
      <p className="text-center text-sm text-fg-muted">
        {copy.switchText}{" "}
        <Link className="text-cyan hover:underline" href={copy.switchHref}>
          {copy.switchCta}
        </Link>
      </p>
    </form>
  );
}

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { ApiError, request } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import { makeT, type MessageKey, type T } from "@/lib/i18n/translate";
import { safeNextPath } from "@/lib/session";

type Mode = "login" | "register";

const COPY: Record<Mode, { title: MessageKey; submit: MessageKey; switchText: MessageKey; switchHref: string; switchCta: MessageKey }> = {
  login: {
    title: "auth.signInTitle",
    submit: "auth.signIn",
    switchText: "auth.newHere",
    switchHref: "/register",
    switchCta: "auth.createAccountLink",
  },
  register: {
    title: "auth.registerTitle",
    submit: "auth.createAccount",
    switchText: "auth.haveAccount",
    switchHref: "/login",
    switchCta: "auth.signIn",
  },
};

/** Maps API problem responses to a form-level message plus per-field messages. */
export function describeError(
  error: unknown,
  t: T = makeT("en"),
): { message: string; fields: Record<string, string> } {
  if (!(error instanceof ApiError)) return { message: t("common.somethingWrong"), fields: {} };
  const fields: Record<string, string> = {};
  for (const e of error.problem.errors ?? []) {
    const key = String(e.loc[e.loc.length - 1]);
    fields[key] =
      key === "password" && e.msg.includes("at least")
        ? t("auth.passwordTooShort")
        : key === "email"
          ? t("auth.invalidEmail")
          : e.msg;
  }
  const message =
    error.status === 429
      ? t("auth.tooManyAttempts")
      : error.problem.code === "validation.failed"
        ? t("auth.checkFields")
        : errorText(error, t);
  return { message, fields };
}

export function AuthForm({ mode, next }: { mode: Mode; next?: string }) {
  const router = useRouter();
  const { t } = useI18n();
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
      setError(describeError(e, t));
      setPending(false);
    }
  }

  return (
    <form method="post" onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      <h1 className="text-xl font-semibold">{t(copy.title)}</h1>
      {error && <Alert>{error.message}</Alert>}
      {mode === "register" && (
        <Field
          label={t("auth.name")}
          name="display_name"
          autoComplete="name"
          required
          error={error?.fields.display_name}
        />
      )}
      <Field
        label={t("auth.workEmail")}
        name="email"
        type="email"
        autoComplete="email"
        required
        error={error?.fields.email}
      />
      <Field
        label={t("auth.password")}
        name="password"
        type="password"
        autoComplete={mode === "login" ? "current-password" : "new-password"}
        hint={mode === "register" ? t("auth.passwordHint") : undefined}
        required
        error={error?.fields.password}
      />
      <Button type="submit" loading={pending}>
        {t(copy.submit)}
      </Button>
      <p className="text-center text-sm text-fg-muted">
        {t(copy.switchText)}{" "}
        <Link className="text-cyan underline underline-offset-2 hover:decoration-2" href={copy.switchHref}>
          {t(copy.switchCta)}
        </Link>
      </p>
    </form>
  );
}

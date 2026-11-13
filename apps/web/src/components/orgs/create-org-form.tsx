"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import type { FormEvent } from "react";

import { describeError } from "@/components/auth/auth-form";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { api } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n/client";

export function CreateOrgForm() {
  const router = useRouter();
  const { t } = useI18n();
  const create = useMutation({
    mutationFn: (name: string) => api.post<{ id: string }>("orgs", { name }),
    onSuccess: (org) => {
      router.push(`/o/${org.id}`);
      router.refresh();
    },
  });
  const err = create.error ? describeError(create.error, t) : null;

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    create.mutate(String(new FormData(e.currentTarget).get("name") ?? ""));
  }

  return (
    <form method="post" onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
      {err && <Alert>{err.message}</Alert>}
      <Field label={t("orgs.nameLabel")} name="name" required minLength={2} error={err?.fields.name} />
      <Button type="submit" loading={create.isPending} className="self-start">
        {t("orgs.create")}
      </Button>
    </form>
  );
}

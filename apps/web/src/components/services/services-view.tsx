"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useState, type FormEvent } from "react";

import { describeError } from "@/components/auth/auth-form";
import { Button } from "@/components/ui/button";
import { Alert, Card, EmptyState } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { DemoTag, HealthPill } from "@/components/ui/status";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";

type Service = components["schemas"]["ServiceOut"];
type Page = { items: Service[]; next_cursor: string | null };

export function ServicesView({ orgId, canManage }: { orgId: string; canManage: boolean }) {
  const qc = useQueryClient();
  const { t, ago } = useI18n();
  const services = useQuery({
    queryKey: ["orgs", orgId, "services"],
    queryFn: () => api.get<Page>(`orgs/${orgId}/services?limit=200`),
    refetchInterval: 30_000, // health changes as alerts fire
  });
  const [open, setOpen] = useState(false);
  const create = useMutation({
    mutationFn: (body: Record<string, string>) => api.post<Service>(`orgs/${orgId}/services`, body),
    onSuccess: () => {
      setOpen(false);
      void qc.invalidateQueries({ queryKey: ["orgs", orgId, "services"] });
    },
  });
  const err = create.error ? describeError(create.error, t) : null;

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(e.currentTarget)) as Record<string, string>;
    for (const k of Object.keys(data)) if (!data[k]) delete data[k];
    create.mutate(data);
  }

  return (
    <div className="space-y-6">
      {canManage && (
        <div>
          {open ? (
            <Card>
              <form method="post" onSubmit={onSubmit} className="grid gap-4 sm:grid-cols-2" noValidate>
                {err && <Alert className="sm:col-span-2">{err.message}</Alert>}
                <Field label={t("common.name")} name="name" required error={err?.fields.name} />
                <Field label={t("services.environment")} name="environment" defaultValue="production" error={err?.fields.environment} />
                <Field label={t("services.repoUrl")} name="repo_url" placeholder="https://github.com/org/repo" error={err?.fields.repo_url} hint={t("services.repoHint")} />
                <Field label={t("services.ownerTeam")} name="owner_team" error={err?.fields.owner_team} />
                <div className="flex gap-2 sm:col-span-2">
                  <Button type="submit" loading={create.isPending}>{t("services.create")}</Button>
                  <Button type="button" variant="ghost" onClick={() => setOpen(false)}>{t("common.cancel")}</Button>
                </div>
              </form>
            </Card>
          ) : (
            <Button onClick={() => setOpen(true)}>{t("services.add")}</Button>
          )}
        </div>
      )}

      {services.isPending ? (
        <div className="space-y-2" role="status" aria-busy aria-label={t("services.loading")}>
          {[0, 1, 2].map((i) => <div key={i} className="h-14 animate-pulse rounded-md bg-raised" />)}
        </div>
      ) : services.isError ? (
        <Alert>
          {t("services.loadError", { error: errorText(services.error, t) })}{" "}
          <Button variant="ghost" size="sm" onClick={() => services.refetch()}>{t("common.retry")}</Button>
        </Alert>
      ) : services.data.items.length === 0 ? (
        <EmptyState
          title={t("services.emptyTitle")}
          description={t("services.emptyBody")}
        />
      ) : (
        <div className="overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full min-w-[640px] text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-fg-subtle">
              <tr className="border-b border-line">
                <th scope="col" className="px-4 py-3 font-medium">{t("services.colService")}</th>
                <th scope="col" className="px-4 py-3 font-medium">{t("services.colHealth")}</th>
                <th scope="col" className="px-4 py-3 font-medium">{t("services.colEnvironment")}</th>
                <th scope="col" className="px-4 py-3 font-medium">{t("services.colTier")}</th>
                <th scope="col" className="px-4 py-3 font-medium">{t("services.colLastData")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {services.data.items.map((s) => (
                <tr key={s.id} className="relative hover:bg-raised">
                  <td className="px-4 py-3">
                    <Link href={`/o/${orgId}/services/${s.id}`} className="font-medium after:absolute after:inset-0">
                      {s.name}
                    </Link>{" "}
                    {s.is_demo && <DemoTag />}
                    <div className="font-mono text-xs text-fg-subtle">{s.slug}</div>
                  </td>
                  <td className="px-4 py-3"><HealthPill health={s.health} /></td>
                  <td className="px-4 py-3 text-fg-muted">{s.environment}</td>
                  <td className="px-4 py-3 text-fg-muted">{s.tier}</td>
                  <td className="px-4 py-3 text-xs text-fg-muted">{ago(s.last_seen_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { describeError } from "@/components/auth/auth-form";
import { Button } from "@/components/ui/button";
import { Alert, Card, EmptyState } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { DemoTag } from "@/components/ui/status";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";

type Key = components["schemas"]["IngestKeyOut"];
type Created = components["schemas"]["IngestKeyCreatedOut"];

export function IngestKeysView({ orgId, apiOrigin }: { orgId: string; apiOrigin: string }) {
  const qc = useQueryClient();
  const { t, ago } = useI18n();
  const keys = useQuery({
    queryKey: ["orgs", orgId, "ingest-keys"],
    queryFn: () => api.get<Key[]>(`orgs/${orgId}/ingest-keys`),
  });
  const [created, setCreated] = useState<Created | null>(null);
  const [copied, setCopied] = useState(false);
  const refresh = () => qc.invalidateQueries({ queryKey: ["orgs", orgId, "ingest-keys"] });
  const create = useMutation({
    mutationFn: (name: string) => api.post<Created>(`orgs/${orgId}/ingest-keys`, { name }),
    onSuccess: (k) => {
      setCreated(k);
      setCopied(false);
      void refresh();
    },
  });
  const revoke = useMutation({
    mutationFn: (id: string) => api.delete(`orgs/${orgId}/ingest-keys/${id}`),
    onSuccess: () => void refresh(),
  });
  const err = create.error ? describeError(create.error, t) : null;

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    create.mutate(String(new FormData(e.currentTarget).get("name") ?? ""));
    e.currentTarget.reset();
  }

  const curl = created
    ? `curl -X POST ${apiOrigin}/ingest/v1/metrics \\
  -H "Authorization: Bearer ${created.key}" \\
  -H "Content-Type: application/json" \\
  -d '{"service":"my-service","points":[{"name":"http.server.requests","ts":"'$(date -u +%FT%TZ)'","value":120}]}'`
    : "";

  return (
    <div className="space-y-6">
      <Card>
        <form method="post" onSubmit={onSubmit} className="flex flex-col gap-3 sm:flex-row sm:items-end" noValidate>
          <div className="flex-1">
            <Field label={t("keys.name")} name="name" placeholder={t("keys.namePlaceholder")} required error={err?.fields.name} />
          </div>
          <Button type="submit" loading={create.isPending}>{t("keys.create")}</Button>
        </form>
        {err && !err.fields.name && <Alert className="mt-3">{err.message}</Alert>}
      </Card>

      {created && (
        <Card className="border-cyan/40">
          <h2 className="text-sm font-semibold">{t("keys.copyNow")}</h2>
          <div className="mt-3 flex items-center gap-2">
            <code className="min-w-0 flex-1 truncate rounded-md bg-canvas px-3 py-2 font-mono text-xs">{created.key}</code>
            <Button
              variant="secondary"
              size="sm"
              onClick={async () => {
                await navigator.clipboard.writeText(created.key);
                setCopied(true);
              }}
            >
              {copied ? t("common.copied") : t("common.copy")}
            </Button>
          </div>
          <p className="mt-4 text-xs text-fg-muted">{t("keys.firstPoint")}</p>
          <pre className="mt-1 overflow-x-auto rounded-md bg-canvas p-3 font-mono text-[11px] leading-relaxed text-fg-muted">{curl}</pre>
        </Card>
      )}

      {keys.isPending ? (
        <div className="h-24 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("keys.loading")} />
      ) : keys.isError ? (
        <Alert>{t("keys.loadError", { error: errorText(keys.error, t) })}</Alert>
      ) : keys.data.length === 0 ? (
        <EmptyState title={t("keys.emptyTitle")} description={t("keys.emptyBody")} />
      ) : (
        <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
          {keys.data.map((k) => (
            <li key={k.id} className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm">
              <div className="min-w-[12rem] flex-1">
                <div className="font-medium">
                  {k.name} {k.is_demo && <DemoTag />}
                </div>
                <div className="break-all font-mono text-xs text-fg-subtle">
                  {k.prefix}… · {k.scopes.join(", ")}
                </div>
              </div>
              <span className="text-xs text-fg-muted">
                {k.revoked_at ? t("keys.revoked") : t("keys.lastUsed", { ago: ago(k.last_used_at) })}
              </span>
              {!k.revoked_at && (
                <Button
                  variant="ghost"
                  size="sm"
                  loading={revoke.isPending && revoke.variables === k.id}
                  onClick={() => {
                    if (window.confirm(t("keys.confirmRevoke", { name: k.name }))) {
                      revoke.mutate(k.id);
                    }
                  }}
                >
                  {t("common.revoke")}
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

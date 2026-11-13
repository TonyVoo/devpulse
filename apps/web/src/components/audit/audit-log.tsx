"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Alert, EmptyState } from "@/components/ui/card";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import type { MessageKey } from "@/lib/i18n/translate";

type Entry = components["schemas"]["AuditLogOut"];
type Page = { items: Entry[]; next_cursor: string | null };

export const FAMILIES = [
  { label: "audit.families.all", prefix: "" },
  { label: "audit.families.members", prefix: "member." },
  { label: "audit.families.invitations", prefix: "invitation." },
  { label: "audit.families.org", prefix: "org." },
  { label: "audit.families.services", prefix: "service." },
  { label: "audit.families.keys", prefix: "ingest_key." },
  { label: "audit.families.rules", prefix: "alert_rule." },
  { label: "audit.families.integrations", prefix: "integration." },
  { label: "audit.families.ai", prefix: "ai." },
] as const satisfies readonly { label: MessageKey; prefix: string }[];

/** Changed keys between two snapshots (shallow), for a compact diff. */
export function diffKeys(before: Record<string, unknown> | null, after: Record<string, unknown> | null): string[] {
  const keys = new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})]);
  return [...keys].filter((k) => JSON.stringify(before?.[k]) !== JSON.stringify(after?.[k])).sort();
}

function show(v: unknown): string {
  if (v === undefined) return "—";
  return typeof v === "string" ? v : JSON.stringify(v);
}

function Row({ e }: { e: Entry }) {
  const [open, setOpen] = useState(false);
  const { t, ago, date } = useI18n();
  const keys = diffKeys(e.before, e.after);
  const who =
    e.actor_name ?? (e.actor_type === "system" ? "DevPulse" : e.actor_type === "ai" ? "Copilot" : t("audit.unknownUser"));
  return (
    <li className="px-4 py-3 text-sm">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-mono text-xs text-cyan">{e.action}</span>
        <span>{who}</span>
        <span className="text-xs text-fg-subtle">
          {e.target_type}
          {e.target_id ? ` · ${e.target_id.slice(0, 8)}` : ""}
        </span>
        <time dateTime={e.created_at} title={date(e.created_at)} className="ml-auto text-xs text-fg-subtle">
          {ago(e.created_at)}
        </time>
      </div>
      {keys.length > 0 && (
        <>
          <button
            type="button"
            aria-expanded={open}
            onClick={() => setOpen((o) => !o)}
            className="mt-1 block text-left text-xs text-fg-muted underline-offset-2 hover:underline"
          >
            {t(open ? "audit.hideChanges" : "audit.showChanges", { keys: keys.join(", ") })}
          </button>
          {open && (
            <table className="mt-2 w-full text-xs">
              <thead className="text-left text-fg-subtle">
                <tr>
                  <th scope="col" className="w-1/4 py-1 font-medium">{t("audit.field")}</th>
                  <th scope="col" className="py-1 font-medium">{t("audit.before")}</th>
                  <th scope="col" className="py-1 font-medium">{t("audit.after")}</th>
                </tr>
              </thead>
              <tbody>
                {keys.map((k) => (
                  <tr key={k} className="align-top">
                    <td className="py-1 font-mono">{k}</td>
                    <td className="break-all py-1 text-critical">{show(e.before?.[k])}</td>
                    <td className="break-all py-1 text-healthy">{show(e.after?.[k])}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </li>
  );
}

export function AuditLog({ orgId }: { orgId: string }) {
  const { t } = useI18n();
  const [family, setFamily] = useState<(typeof FAMILIES)[number]>(FAMILIES[0]);
  const q = useInfiniteQuery({
    queryKey: ["orgs", orgId, "audit", family.prefix],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => {
      const params = new URLSearchParams({ limit: "50" });
      if (family.prefix) params.set("action_prefix", family.prefix);
      if (pageParam) params.set("cursor", pageParam);
      return api.get<Page>(`orgs/${orgId}/audit-logs?${params}`);
    },
    getNextPageParam: (last) => last.next_cursor,
  });
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div className="space-y-4">
      <label className="flex max-w-xs flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
        {t("audit.show")}
        <Select
          value={family.label}
          onChange={(e) => setFamily(FAMILIES.find((f) => f.label === e.target.value) ?? FAMILIES[0])}
        >
          {FAMILIES.map((f) => (
            <option key={f.label} value={f.label}>
              {t(f.label)}
            </option>
          ))}
        </Select>
      </label>
      {q.isPending ? (
        <div className="h-40 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("audit.loading")} />
      ) : q.isError ? (
        <Alert>
          {t("audit.loadError", { error: errorText(q.error, t) })}{" "}
          <Button variant="ghost" size="sm" onClick={() => q.refetch()}>{t("common.retry")}</Button>
        </Alert>
      ) : items.length === 0 ? (
        <EmptyState title={t("audit.emptyTitle")} description={t("audit.emptyBody")} />
      ) : (
        <>
          <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
            {items.map((e) => (
              <Row key={e.id} e={e} />
            ))}
          </ul>
          {q.hasNextPage && (
            <Button variant="secondary" loading={q.isFetchingNextPage} onClick={() => q.fetchNextPage()}>
              {t("audit.loadOlder")}
            </Button>
          )}
        </>
      )}
    </div>
  );
}

"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Alert, EmptyState } from "@/components/ui/card";
import { timeAgo } from "@/components/ui/status";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Entry = components["schemas"]["AuditLogOut"];
type Page = { items: Entry[]; next_cursor: string | null };

export const FAMILIES = [
  { label: "All", prefix: "" },
  { label: "Members", prefix: "member." },
  { label: "Invitations", prefix: "invitation." },
  { label: "Organization", prefix: "org." },
  { label: "Services", prefix: "service." },
  { label: "Ingest keys", prefix: "ingest_key." },
  { label: "Alert rules", prefix: "alert_rule." },
  { label: "Integrations", prefix: "integration." },
  { label: "AI", prefix: "ai." },
] as const;

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
  const keys = diffKeys(e.before, e.after);
  const who = e.actor_name ?? (e.actor_type === "system" ? "DevPulse" : e.actor_type === "ai" ? "Copilot" : "Unknown user");
  return (
    <li className="px-4 py-3 text-sm">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-mono text-xs text-cyan">{e.action}</span>
        <span>{who}</span>
        <span className="text-xs text-fg-subtle">
          {e.target_type}
          {e.target_id ? ` · ${e.target_id.slice(0, 8)}` : ""}
        </span>
        <time dateTime={e.created_at} title={new Date(e.created_at).toLocaleString()} className="ml-auto text-xs text-fg-subtle">
          {timeAgo(e.created_at)}
        </time>
      </div>
      {keys.length > 0 && (
        <>
          <button
            type="button"
            aria-expanded={open}
            onClick={() => setOpen((o) => !o)}
            className="mt-1 text-xs text-fg-muted underline-offset-2 hover:underline"
          >
            {open ? "Hide" : "Show"} changes ({keys.join(", ")})
          </button>
          {open && (
            <table className="mt-2 w-full text-xs">
              <thead className="text-left text-fg-subtle">
                <tr>
                  <th scope="col" className="w-1/4 py-1 font-medium">Field</th>
                  <th scope="col" className="py-1 font-medium">Before</th>
                  <th scope="col" className="py-1 font-medium">After</th>
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
        Show
        <select
          value={family.label}
          onChange={(e) => setFamily(FAMILIES.find((f) => f.label === e.target.value) ?? FAMILIES[0])}
          className="min-h-10 rounded-md border border-line bg-canvas px-2 text-sm text-fg"
        >
          {FAMILIES.map((f) => (
            <option key={f.label}>{f.label}</option>
          ))}
        </select>
      </label>
      {q.isPending ? (
        <div className="h-40 animate-pulse rounded-md bg-surface" role="status" aria-busy aria-label="Loading audit log" />
      ) : q.isError ? (
        <Alert>
          Couldn&apos;t load the audit log: {q.error.message}{" "}
          <Button variant="ghost" size="sm" onClick={() => q.refetch()}>Retry</Button>
        </Alert>
      ) : items.length === 0 ? (
        <EmptyState title="Nothing recorded yet" description="Changes to members, settings, rules and integrations appear here." />
      ) : (
        <>
          <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
            {items.map((e) => (
              <Row key={e.id} e={e} />
            ))}
          </ul>
          {q.hasNextPage && (
            <Button variant="secondary" loading={q.isFetchingNextPage} onClick={() => q.fetchNextPage()}>
              Load older entries
            </Button>
          )}
        </>
      )}
    </div>
  );
}

"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Alert, EmptyState } from "@/components/ui/card";
import { DemoTag, IncidentStatusBadge, SeverityChip } from "@/components/ui/status";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import type { MessageKey } from "@/lib/i18n/translate";
import { cn } from "@/lib/utils";

type Incident = components["schemas"]["IncidentOut"];
type Page = { items: Incident[]; next_cursor: string | null };

const TABS = [
  { label: "incidents.open", query: "status=triggered&status=acknowledged" },
  { label: "incidents.resolved", query: "status=resolved" },
  { label: "incidents.all", query: "" },
] as const satisfies readonly { label: MessageKey; query: string }[];

/** Incident list for the dashboard; each incident opens its detail page. */
export function IncidentsView({ orgId }: { orgId: string }) {
  const { t, ago } = useI18n();
  const [tab, setTab] = useState<(typeof TABS)[number]>(TABS[0]);
  const incidents = useQuery({
    queryKey: ["orgs", orgId, "incidents", tab.label],
    queryFn: () => api.get<Page>(`orgs/${orgId}/incidents?limit=100${tab.query ? `&${tab.query}` : ""}`),
    refetchInterval: 30_000,
  });

  return (
    <div className="space-y-4">
      <div role="tablist" aria-label={t("incidents.tabs")} className="flex gap-1">
        {TABS.map((tab_) => (
          <button
            key={tab_.label}
            role="tab"
            aria-selected={tab_.label === tab.label}
            onClick={() => setTab(tab_)}
            className={cn(
              "rounded-md px-3 py-1.5 text-sm",
              tab_.label === tab.label ? "bg-raised text-fg" : "text-fg-muted hover:text-fg",
            )}
          >
            {t(tab_.label)}
          </button>
        ))}
      </div>
      {incidents.isPending ? (
        <div className="h-32 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("incidents.loading")} />
      ) : incidents.isError ? (
        <Alert>
          {t("incidents.loadError", { error: errorText(incidents.error, t) })}{" "}
          <Button variant="ghost" size="sm" onClick={() => incidents.refetch()}>{t("common.retry")}</Button>
        </Alert>
      ) : incidents.data.items.length === 0 ? (
        <EmptyState
          title={tab.label === "incidents.open" ? t("incidents.emptyOpen") : t("incidents.empty")}
          description={t("incidents.emptyBody")}
        />
      ) : (
        <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
          {incidents.data.items.map((i) => (
            <li key={i.id} className="relative flex flex-wrap items-center gap-3 px-4 py-3 text-sm hover:bg-raised">
              <SeverityChip severity={i.severity} />
              <div className="min-w-0 flex-1">
                <div className="font-medium">
                  {/* The link covers the whole row (stretched), so the row is one large target. */}
                  <Link href={`/o/${orgId}/incidents/${i.key}`} className="after:absolute after:inset-0">
                    {i.title}
                  </Link>{" "}
                  {i.is_demo && <DemoTag />}
                </div>
                <div className="text-xs text-fg-subtle">
                  <span className="font-mono">{i.key}</span>
                  {i.service && ` · ${i.service.name}`} · {ago(i.started_at)}
                  {i.assignee && ` · ${i.assignee.display_name}`}
                </div>
              </div>
              <IncidentStatusBadge status={i.status} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

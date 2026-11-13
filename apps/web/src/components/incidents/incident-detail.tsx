"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";

import { AiPanel } from "@/components/ai/ai-panel";
import { ActionsBar, Comments, CorrelationPanel } from "@/components/incidents/incident-panels";
import { Button } from "@/components/ui/button";
import { Alert, EmptyState } from "@/components/ui/card";
import { DemoTag, IncidentStatusBadge, SeverityChip } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import { makeT, type T } from "@/lib/i18n/translate";

type Incident = components["schemas"]["IncidentOut"];
type Event = components["schemas"]["EventOut"];

/** Human sentence for a timeline entry (mirrors the mobile app). */
export function describeEvent(e: Event, t: T = makeT("en")): string {
  const d = (e.data ?? {}) as Record<string, unknown>;
  const who =
    e.actor?.display_name ?? (e.actor_type === "system" ? "DevPulse" : e.actor_type === "ai" ? "Copilot" : t("events.someone"));
  const rule = String(d.rule ?? t("events.rule"));
  switch (e.type) {
    case "created":
      return d.rule ? t("events.openedByRule", { rule }) : t("events.openedBy", { who });
    case "acknowledged":
      return t("events.acknowledged", { who });
    case "resolved":
      return t("events.resolved", { who });
    case "reopened":
      return t("events.reopened", { who });
    case "assigned":
      return d.assignee_name ? t("events.assigned", { who, name: String(d.assignee_name) }) : t("events.unassigned", { who });
    case "escalated":
      return t("events.escalated", { who, level: String(d.level) });
    case "severity_changed":
      return t("events.severityChanged", { who, severity: String(d.to).toUpperCase() });
    case "comment_added":
      return t("events.commented", { who });
    case "alert_attached":
      return t("events.alertAttached", { rule });
    case "alert_resolved":
      return t("events.alertResolved", { rule });
    case "deployment_correlated":
      return t("events.deploymentCorrelated", { version: String(d.version) });
    case "ai_analysis":
      if (d.kind === "proposal_decision") {
        const description = String(d.description);
        return d.decision === "approved"
          ? t("events.proposalApproved", { who, description })
          : t("events.proposalRejected", { who, description });
      }
      return d.status === "succeeded" ? t("events.aiReady") : t("events.aiUnavailable");
    default:
      return String(e.type).replaceAll("_", " "); // future event types
  }
}

export function IncidentDetail({
  orgId,
  incidentRef,
  canAct,
  isAdmin,
  myUserId,
}: {
  orgId: string;
  incidentRef: string;
  canAct: boolean;
  isAdmin: boolean;
  myUserId: string;
}) {
  const { t, ago } = useI18n();
  const incident = useQuery({
    queryKey: ["orgs", orgId, "incident", incidentRef],
    queryFn: () => api.get<Incident>(`orgs/${orgId}/incidents/${incidentRef}`),
    refetchInterval: 30_000,
  });
  const timeline = useQuery({
    queryKey: ["orgs", orgId, "incident", incidentRef, "timeline"],
    queryFn: () => api.get<{ items: Event[] }>(`orgs/${orgId}/incidents/${incidentRef}/timeline?limit=200`),
    refetchInterval: 15_000,
  });

  if (incident.isPending) {
    return <div className="h-32 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("incident.loading")} />;
  }
  if (incident.isError) {
    return incident.error instanceof ApiError && incident.error.status === 404 ? (
      <EmptyState title={t("incident.notFoundTitle")} description={t("incident.notFoundBody")} />
    ) : (
      <Alert>
        {t("incident.loadError", { error: errorText(incident.error, t) })}{" "}
        <Button variant="ghost" size="sm" onClick={() => incident.refetch()}>{t("common.retry")}</Button>
      </Alert>
    );
  }
  const i = incident.data;
  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
      <div className="min-w-0 space-y-6">
        <header className="space-y-2">
          <Link href={`/o/${orgId}/incidents`} className="text-xs text-fg-subtle hover:text-fg">
            {t("incident.back")}
          </Link>
          <div className="flex flex-wrap items-center gap-2">
            <SeverityChip severity={i.severity} />
            <span className="font-mono text-sm text-fg-muted">{i.key}</span>
            <IncidentStatusBadge status={i.status} />
            {i.is_demo && <DemoTag />}
          </div>
          <h1 className="text-2xl font-semibold">{i.title}</h1>
          <p className="text-xs text-fg-subtle">
            {i.service && `${i.service.name} · `}
            {t("incident.started", { ago: ago(i.started_at) })}
            {i.assignee && ` · ${t("incident.owner", { name: i.assignee.display_name })}`}
          </p>
          {i.summary && <p className="text-sm">{i.summary}</p>}
          {i.root_cause_confirmed && (
            <Alert tone="info">{t("incident.rootCause", { cause: i.root_cause_confirmed })}</Alert>
          )}
          {canAct && <ActionsBar orgId={orgId} incident={i} myUserId={myUserId} />}
        </header>
        <CorrelationPanel orgId={orgId} incident={i} />
        <AiPanel orgId={orgId} incidentRef={i.key} canAct={canAct} isAdmin={isAdmin} />
      </div>
      <aside aria-label={t("incident.timelineAndComments")} className="min-w-0 space-y-6 lg:sticky lg:top-6 lg:self-start">
        <h2 className="text-sm font-semibold">{t("incident.timeline")}</h2>
        {timeline.isError ? (
          <Alert>{t("incident.timelineError")}</Alert>
        ) : (
          <ol className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
            {(timeline.data?.items ?? []).map((e) => (
              <li key={e.id} className="flex justify-between gap-2 px-3 py-2">
                <span>{describeEvent(e, t)}</span>
                <span className="shrink-0 text-xs text-fg-subtle">{ago(e.created_at)}</span>
              </li>
            ))}
          </ol>
        )}
        <Comments orgId={orgId} incidentRef={i.key} canAct={canAct} />
      </aside>
    </div>
  );
}

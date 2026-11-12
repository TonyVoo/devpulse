"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";

import { AiPanel } from "@/components/ai/ai-panel";
import { ActionsBar, Comments, CorrelationPanel } from "@/components/incidents/incident-panels";
import { Button } from "@/components/ui/button";
import { Alert, EmptyState } from "@/components/ui/card";
import { DemoTag, IncidentStatusBadge, SeverityChip, timeAgo } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Incident = components["schemas"]["IncidentOut"];
type Event = components["schemas"]["EventOut"];

/** Human sentence for a timeline entry (mirrors the mobile app). */
export function describeEvent(e: Event): string {
  const d = (e.data ?? {}) as Record<string, unknown>;
  const who = e.actor?.display_name ?? (e.actor_type === "system" ? "DevPulse" : e.actor_type === "ai" ? "Copilot" : "Someone");
  switch (e.type) {
    case "created":
      return d.rule ? `Opened by alert “${String(d.rule)}”` : `Opened by ${who}`;
    case "acknowledged":
      return `${who} acknowledged`;
    case "resolved":
      return `${who} resolved`;
    case "reopened":
      return `${who} reopened`;
    case "assigned":
      return d.assignee_name ? `${who} assigned ${String(d.assignee_name)}` : `${who} unassigned`;
    case "escalated":
      return `${who} escalated to level ${String(d.level)}`;
    case "severity_changed":
      return `${who} changed severity to ${String(d.to).toUpperCase()}`;
    case "comment_added":
      return `${who} commented`;
    case "alert_attached":
      return `Alert “${String(d.rule ?? "rule")}” fired again`;
    case "alert_resolved":
      return `Alert “${String(d.rule ?? "rule")}” recovered`;
    case "deployment_correlated":
      return `Deployment ${String(d.version)} may be related`;
    case "ai_analysis":
      if (d.kind === "proposal_decision") return `${who} ${String(d.decision)} the AI-proposed step “${String(d.description)}”`;
      return d.status === "succeeded" ? "AI analysis ready" : "AI analysis unavailable";
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
    return <div className="h-32 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label="Loading incident" />;
  }
  if (incident.isError) {
    return incident.error instanceof ApiError && incident.error.status === 404 ? (
      <EmptyState title="Incident not found" description="It may belong to another organization." />
    ) : (
      <Alert>
        Couldn&apos;t load the incident: {incident.error.message}{" "}
        <Button variant="ghost" size="sm" onClick={() => incident.refetch()}>Retry</Button>
      </Alert>
    );
  }
  const i = incident.data;
  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
      <div className="min-w-0 space-y-6">
        <header className="space-y-2">
          <Link href={`/o/${orgId}/incidents`} className="text-xs text-fg-subtle hover:text-fg">
            ← Incidents
          </Link>
          <div className="flex flex-wrap items-center gap-2">
            <SeverityChip severity={i.severity} />
            <span className="font-mono text-sm text-fg-muted">{i.key}</span>
            <IncidentStatusBadge status={i.status} />
            {i.is_demo && <DemoTag />}
          </div>
          <h1 className="text-2xl font-semibold">{i.title}</h1>
          <p className="text-xs text-fg-subtle">
            {i.service && `${i.service.name} · `}started {timeAgo(i.started_at)}
            {i.assignee && ` · owner ${i.assignee.display_name}`}
          </p>
          {i.summary && <p className="text-sm">{i.summary}</p>}
          {i.root_cause_confirmed && (
            <Alert tone="info">Root cause confirmed by the team: {i.root_cause_confirmed}</Alert>
          )}
          {canAct && <ActionsBar orgId={orgId} incident={i} myUserId={myUserId} />}
        </header>
        <CorrelationPanel orgId={orgId} incident={i} />
        <AiPanel orgId={orgId} incidentRef={i.key} canAct={canAct} isAdmin={isAdmin} />
      </div>
      <aside aria-label="Timeline and comments" className="min-w-0 space-y-6 lg:sticky lg:top-6 lg:self-start">
        <h2 className="text-sm font-semibold">Timeline</h2>
        {timeline.isError ? (
          <Alert>Couldn&apos;t load the timeline.</Alert>
        ) : (
          <ol className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
            {(timeline.data?.items ?? []).map((e) => (
              <li key={e.id} className="flex justify-between gap-2 px-3 py-2">
                <span>{describeEvent(e)}</span>
                <span className="shrink-0 text-xs text-fg-subtle">{timeAgo(e.created_at)}</span>
              </li>
            ))}
          </ol>
        )}
        <Comments orgId={orgId} incidentRef={i.key} canAct={canAct} />
      </aside>
    </div>
  );
}

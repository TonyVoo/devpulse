"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { fmt as chartFmt, type Marker, TimeSeriesChart, toPoints } from "@/components/charts/time-series";
import { Button, buttonVariants } from "@/components/ui/button";
import { Alert, Card, EmptyState } from "@/components/ui/card";
import { DemoTag, HealthPill, IncidentStatusBadge, SeverityChip, timeAgo } from "@/components/ui/status";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { cn } from "@/lib/utils";

type Overview = components["schemas"]["OverviewOut"];
type Window = Overview["window"];

const WINDOWS: { value: Window; label: string }[] = [
  { value: "1h", label: "1h" },
  { value: "24h", label: "24h" },
  { value: "7d", label: "7d" },
];

export function kpi(n: number | null | undefined, kind: "count" | "pct" | "ms"): string {
  if (n === null || n === undefined) return "—";
  if (kind === "pct") return chartFmt.pct(n);
  if (kind === "ms") return chartFmt.ms(n);
  return chartFmt.count(n);
}

/** Org overview: KPIs, request volume with deploys, health and recent activity. Live (30 s). */
export function OverviewView({ orgId }: { orgId: string }) {
  const [window, setWindow] = useState<Window>("24h");
  const q = useQuery({
    queryKey: ["orgs", orgId, "overview", window],
    queryFn: () => api.get<Overview>(`orgs/${orgId}/overview?window=${window}`),
    refetchInterval: 30_000,
    placeholderData: (prev) => prev,
  });
  const base = `/o/${orgId}`;

  if (q.isPending) {
    return <div className="h-64 animate-pulse rounded-lg bg-raised" role="status" aria-busy aria-label="Loading overview" />;
  }
  if (q.isError) {
    return (
      <Alert>
        Couldn&apos;t load the overview: {q.error.message}{" "}
        <Button variant="ghost" size="sm" onClick={() => q.refetch()}>Retry</Button>
      </Alert>
    );
  }
  const o = q.data;
  if (o.services_total === 0) {
    return (
      <EmptyState
        title="No services connected yet"
        description="Add a service and an ingest key, then send telemetry. Health, latency and incidents will appear here."
        action={
          <Link href={`${base}/services`} className={buttonVariants({ variant: "secondary" })}>
            Add a service
          </Link>
        }
      />
    );
  }

  const open = Object.values(o.open_incidents_by_severity).reduce((a, b) => a + (b ?? 0), 0);
  const urgent = (o.open_incidents_by_severity.sev1 ?? 0) + (o.open_incidents_by_severity.sev2 ?? 0);
  const label = window === "1h" ? "last hour" : window === "24h" ? "last 24 hours" : "last 7 days";
  // Bucket size per window (matches the API's request series).
  const stepMs = { "1h": 60_000, "24h": 1_800_000, "7d": 21_600_000 }[window];
  const points = toPoints(o.request_series, stepMs);
  const domainEnd = new Date(o.generated_at).getTime();
  const span = { "1h": 3_600_000, "24h": 86_400_000, "7d": 604_800_000 }[window];
  const markers: Marker[] = o.recent_deployments
    .filter((d) => new Date(d.started_at).getTime() >= domainEnd - span)
    .map((d) => ({ t: new Date(d.started_at).getTime(), label: d.version, tone: "deploy" as const }));

  const cards: { label: string; value: string; href: string; tone?: string }[] = [
    { label: `Requests (${window})`, value: kpi(o.totals.requests, "count"), href: `${base}/services` },
    { label: "Error rate", value: kpi(o.totals.error_rate, "pct"), href: `${base}/services` },
    { label: "Avg latency", value: kpi(o.totals.latency_avg_ms, "ms"), href: `${base}/services` },
    { label: "Open incidents", value: String(open), href: `${base}/incidents`, tone: urgent ? "text-critical" : undefined },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div role="radiogroup" aria-label="Time window" className="flex gap-1">
          {WINDOWS.map((w) => (
            <button
              key={w.value}
              role="radio"
              aria-checked={w.value === window}
              onClick={() => setWindow(w.value)}
              className={cn(
                "min-h-9 rounded-md px-3 text-sm",
                w.value === window ? "bg-raised text-fg" : "text-fg-muted hover:text-fg",
              )}
            >
              {w.label}
            </button>
          ))}
        </div>
        <p className="text-xs text-fg-subtle" aria-live="polite">
          Updated {timeAgo(o.generated_at)} · refreshes every 30 s
        </p>
      </div>

      {urgent > 0 && (
        <Alert>
          {urgent} critical or major incident{urgent === 1 ? " is" : "s are"} open.{" "}
          <Link href={`${base}/incidents`} className="font-medium underline underline-offset-2">
            View incidents
          </Link>
        </Alert>
      )}

      <section aria-label={`Key numbers, ${label}`} className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {cards.map((c) => (
          <Link
            key={c.label}
            href={c.href}
            className="min-w-0 rounded-lg border border-line bg-surface p-4 transition-colors hover:border-cyan/50"
          >
            <p className="truncate text-xs text-fg-muted">{c.label}</p>
            <p className={cn("mt-1 truncate font-mono text-xl tabular-nums sm:text-2xl", c.tone)}>{c.value}</p>
          </Link>
        ))}
      </section>

      <Card className="min-w-0 p-4">
        <TimeSeriesChart
          title={`Requests per interval, ${label}`}
          points={points}
          format={chartFmt.count}
          markers={markers}
          domain={[domainEnd - span, domainEnd]}
          height={220}
        />
      </Card>

      <section className="grid gap-4 lg:grid-cols-3">
        <Card className="min-w-0 p-4">
          <h2 className="mb-3 text-sm font-semibold">Service health</h2>
          <ul className="space-y-1 text-sm">
            {(["critical", "degraded", "healthy", "unknown"] as const).map((h) => (
              <li key={h}>
                <Link href={`${base}/services`} className="flex items-center justify-between rounded-md px-2 py-1.5 hover:bg-raised">
                  <HealthPill health={h} />
                  <span className="font-mono tabular-nums">{o.services_by_health[h] ?? 0}</span>
                </Link>
              </li>
            ))}
          </ul>
        </Card>
        <Card className="min-w-0 p-4 lg:col-span-2">
          <h2 className="mb-3 text-sm font-semibold">Recent incidents</h2>
          {o.recent_incidents.length === 0 ? (
            <p className="text-sm text-fg-muted">No incidents. All clear.</p>
          ) : (
            <ul className="space-y-1 text-sm">
              {o.recent_incidents.map((i) => (
                <li key={i.id}>
                  <Link href={`${base}/incidents/${i.key}`} className="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-raised">
                    <SeverityChip severity={i.severity} />
                    <span className="min-w-0 flex-1 truncate" title={i.title}>
                      {i.title}
                    </span>
                    <IncidentStatusBadge status={i.status} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card className="min-w-0 p-4 lg:col-span-3">
          <h2 className="mb-3 text-sm font-semibold">Recent deployments</h2>
          {o.recent_deployments.length === 0 ? (
            <p className="text-sm text-fg-muted">No deployments recorded.</p>
          ) : (
            <ul className="space-y-1 text-sm">
              {o.recent_deployments.slice(0, 6).map((d) => (
                <li key={d.id}>
                  <Link href={`${base}/services/${d.service_id}`} className="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-raised">
                    <span className="min-w-0 flex-1 truncate">
                      <span className="font-mono">{d.version}</span> <span className="text-fg-muted">{d.service_name}</span>
                    </span>
                    {d.is_demo && <DemoTag />}
                    <span className="shrink-0 text-xs text-fg-subtle">{timeAgo(d.started_at)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </section>
    </div>
  );
}

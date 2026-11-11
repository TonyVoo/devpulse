import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { Card, EmptyState } from "@/components/ui/card";
import { HealthPill, SeverityChip, timeAgo } from "@/components/ui/status";
import type { components } from "@/lib/api-types";
import { getMe, serverGet } from "@/lib/server-api";

type Overview = components["schemas"]["OverviewOut"];

function fmt(n: number | null | undefined, kind: "count" | "pct" | "ms"): string {
  if (n === null || n === undefined) return "—";
  if (kind === "pct") return `${(n * 100).toFixed(n < 0.01 ? 2 : 1)}%`;
  if (kind === "ms") return n >= 1000 ? `${(n / 1000).toFixed(2)} s` : `${Math.round(n)} ms`;
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n));
}

export default async function OrgOverview({ params }: PageProps<"/o/[orgId]">) {
  const { orgId } = await params;
  const [me, o] = await Promise.all([getMe(), serverGet<Overview>(`orgs/${orgId}/overview?window=24h`)]);
  const org = me.memberships.find((m) => m.id === orgId);
  const open = Object.values(o.open_incidents_by_severity).reduce((a, b) => a + (b ?? 0), 0);

  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <p className="font-mono text-xs uppercase tracking-widest text-fg-subtle">{org?.slug}</p>
        <h1 className="text-2xl font-semibold">{org?.name}</h1>
      </header>
      {o.services_total === 0 ? (
        <EmptyState
          title="No services connected yet"
          description="Add a service and an ingest key, then send telemetry. Health, latency and incidents will appear here."
          action={
            <Link href={`/o/${orgId}/services`} className={buttonVariants({ variant: "secondary" })}>
              Add a service
            </Link>
          }
        />
      ) : (
        <>
          <section aria-label="Last 24 hours" className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {[
              ["Requests (24h)", fmt(o.totals.requests, "count")],
              ["Error rate", fmt(o.totals.error_rate, "pct")],
              ["Avg latency", fmt(o.totals.latency_avg_ms, "ms")],
              ["Open incidents", String(open)],
            ].map(([label, value]) => (
              <Card key={label} className="p-4">
                <p className="text-xs text-fg-muted">{label}</p>
                <p className="mt-1 font-mono text-2xl tabular-nums">{value}</p>
              </Card>
            ))}
          </section>
          <section className="grid gap-4 lg:grid-cols-2">
            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Service health</h2>
              <ul className="space-y-2 text-sm">
                {(["critical", "degraded", "healthy", "unknown"] as const).map((h) => (
                  <li key={h} className="flex items-center justify-between">
                    <HealthPill health={h} />
                    <span className="font-mono tabular-nums">{o.services_by_health[h] ?? 0}</span>
                  </li>
                ))}
              </ul>
            </Card>
            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Recent incidents</h2>
              {o.recent_incidents.length === 0 ? (
                <p className="text-sm text-fg-muted">No incidents.</p>
              ) : (
                <ul className="space-y-2 text-sm">
                  {o.recent_incidents.map((i) => (
                    <li key={i.id} className="flex items-center gap-2">
                      <SeverityChip severity={i.severity} />
                      <span className="min-w-0 flex-1 truncate">{i.title}</span>
                      <span className="text-xs text-fg-subtle">{timeAgo(i.started_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </section>
        </>
      )}
    </div>
  );
}

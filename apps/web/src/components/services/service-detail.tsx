"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { type Marker, MarkerLegend, TimeSeriesChart, toPoints } from "@/components/charts/time-series";
import { Button } from "@/components/ui/button";
import { Alert, EmptyState } from "@/components/ui/card";
import { DemoTag, HealthPill, SeverityChip } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import { type MessageKey, tOr } from "@/lib/i18n/translate";

type Service = components["schemas"]["ServiceOut"];
type Metrics = components["schemas"]["MetricsOut"];
type Deployment = components["schemas"]["DeploymentOut"];
type Incident = components["schemas"]["IncidentOut"];

export const RANGES = [
  { label: "1h", ms: 3_600_000 },
  { label: "6h", ms: 6 * 3_600_000 },
  { label: "24h", ms: 24 * 3_600_000 },
  { label: "7d", ms: 7 * 24 * 3_600_000 },
] as const;

export const CHARTS = [
  { spec: "http.server.duration_ms:p95", title: "service.latencyP95", format: "ms" },
  { spec: "http.server.error_rate", title: "service.errorRate", format: "pct" },
  { spec: "http.server.requests:sum", title: "service.requests", format: "count" },
  { spec: "process.cpu.utilization:avg", title: "service.cpu", format: "pct" },
] as const satisfies readonly { spec: string; title: MessageKey; format: "ms" | "pct" | "count" }[];

/** Metric query string for `/metrics` (repeated `names`). */
export function metricsQuery(specs: readonly string[], from: Date, to: Date): string {
  const p = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  specs.forEach((s) => p.append("names", s));
  return p.toString();
}

export function ServiceDetail({ orgId, serviceId }: { orgId: string; serviceId: string }) {
  const { t, fmt, ago } = useI18n();
  const [range, setRange] = useState<(typeof RANGES)[number]>(RANGES[1]);
  // The window moves with time: recomputed on every (auto)refresh, never on re-render.
  const [tick, setTick] = useState(0);

  const service = useQuery({
    queryKey: ["orgs", orgId, "service", serviceId],
    queryFn: () => api.get<Service>(`orgs/${orgId}/services/${serviceId}`),
  });
  const metrics = useQuery({
    queryKey: ["orgs", orgId, "service", serviceId, "metrics", range.label, tick],
    queryFn: () => {
      const to = new Date();
      const from = new Date(to.getTime() - range.ms);
      return api.get<Metrics>(
        `orgs/${orgId}/services/${serviceId}/metrics?${metricsQuery(CHARTS.map((c) => c.spec), from, to)}`,
      );
    },
    enabled: service.isSuccess,
    refetchInterval: 60_000, // live: the window slides forward every minute
    placeholderData: (prev) => prev,
  });
  const deployments = useQuery({
    queryKey: ["orgs", orgId, "service", serviceId, "deployments"],
    queryFn: () => api.get<{ items: Deployment[] }>(`orgs/${orgId}/deployments?service_id=${serviceId}&limit=100`),
    enabled: service.isSuccess,
  });
  const incidents = useQuery({
    queryKey: ["orgs", orgId, "service", serviceId, "incidents"],
    queryFn: () => api.get<{ items: Incident[] }>(`orgs/${orgId}/incidents?service_id=${serviceId}&limit=50`),
    enabled: service.isSuccess,
  });

  if (service.isPending) return <div className="h-32 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("service.loading")} />;
  if (service.isError) {
    return service.error instanceof ApiError && service.error.status === 404 ? (
      <EmptyState title={t("service.notFoundTitle")} description={t("service.notFoundBody")} />
    ) : (
      <Alert>{t("service.loadError", { error: errorText(service.error, t) })}</Alert>
    );
  }
  const s = service.data;
  const to = metrics.data ? new Date(metrics.data.to) : new Date();
  const from = metrics.data ? new Date(metrics.data.from_) : new Date(to.getTime() - range.ms);
  const inRange = (iso: string) => {
    const t = new Date(iso).getTime();
    return t >= from.getTime() && t <= to.getTime();
  };
  const markers: Marker[] = [
    ...(deployments.data?.items ?? [])
      .filter((d) => inRange(d.started_at))
      .map((d) => ({ t: new Date(d.started_at).getTime(), label: d.version, tone: "deploy" as const })),
    ...(incidents.data?.items ?? [])
      .filter((i) => inRange(i.started_at))
      .map((i) => ({ t: new Date(i.started_at).getTime(), label: i.key, tone: "incident" as const })),
  ];
  const series = new Map((metrics.data?.series ?? []).map((x) => [`${x.name}:${x.aggregation}`, x]));
  const find = (spec: string) =>
    series.get(spec) ?? (metrics.data?.series ?? []).find((x) => spec.startsWith(x.name));

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <Link href={`/o/${orgId}/services`} className="text-xs text-fg-subtle hover:text-fg">
          {t("service.back")}
        </Link>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">{s.name}</h1>
          <HealthPill health={s.health} />
          {s.is_demo && <DemoTag />}
        </div>
        <p className="text-xs text-fg-subtle">
          <span className="font-mono">{s.slug}</span> · {t("service.meta", { environment: s.environment, tier: s.tier })}
          {s.owner_team && ` · ${s.owner_team}`} · {t("service.lastData", { ago: ago(s.last_seen_at) })}
        </p>
      </header>

      <div className="flex flex-wrap items-center gap-2">
        <div role="radiogroup" aria-label={t("service.range")} className="flex gap-1">
          {RANGES.map((r) => (
            <button
              key={r.label}
              role="radio"
              aria-checked={r.label === range.label}
              onClick={() => setRange(r)}
              className={
                r.label === range.label ? "rounded-md bg-raised px-3 py-1.5 text-sm text-fg" : "rounded-md px-3 py-1.5 text-sm text-fg-muted hover:text-fg"
              }
            >
              {r.label}
            </button>
          ))}
        </div>
        <Button size="sm" variant="ghost" onClick={() => setTick((t) => t + 1)}>
          {t("common.refresh")}
        </Button>
        <MarkerLegend />
        <span className="text-xs text-fg-subtle">{t("service.updatesEveryMinute")}</span>
      </div>

      {metrics.isError ? (
        <Alert>{t("service.metricsError", { error: errorText(metrics.error, t) })}</Alert>
      ) : (
        <div className="grid min-w-0 gap-6 lg:grid-cols-2" aria-busy={metrics.isPending}>
          {CHARTS.map((c) => (
            <div key={c.spec} className="min-w-0 rounded-lg border border-line bg-surface p-4">
              <TimeSeriesChart
                title={t(c.title)}
                points={toPoints(find(c.spec)?.points, (metrics.data?.step_s ?? 0) * 1000 || undefined)}
                format={fmt[c.format]}
                markers={markers}
                domain={[from.getTime(), to.getTime()]}
                loading={metrics.isPending}
              />
            </div>
          ))}
        </div>
      )}
      {metrics.data?.approximate_percentiles && (
        <p className="text-xs text-fg-subtle">{t("service.approximate")}</p>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <section aria-labelledby="deploys" className="min-w-0 space-y-2">
          <h2 id="deploys" className="text-sm font-semibold">{t("service.recentDeployments")}</h2>
          {(deployments.data?.items ?? []).length === 0 ? (
            <p className="text-sm text-fg-subtle">{t("service.noDeployments")}</p>
          ) : (
            <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
              {deployments.data!.items.slice(0, 10).map((d) => (
                <li key={d.id} className="flex justify-between gap-2 px-3 py-2">
                  <span className="min-w-0 truncate">
                    <span className="font-mono">{d.version}</span>{" "}
                    <span className="text-fg-subtle">{d.commit_message?.split("\n")[0]}</span>
                  </span>
                  <span className="shrink-0 text-xs text-fg-subtle">
                    {tOr(t, `deployStatus.${d.status}`, d.status)} · {ago(d.started_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
        <section aria-labelledby="incs" className="min-w-0 space-y-2">
          <h2 id="incs" className="text-sm font-semibold">{t("service.incidents")}</h2>
          {(incidents.data?.items ?? []).length === 0 ? (
            <p className="text-sm text-fg-subtle">{t("service.noIncidents")}</p>
          ) : (
            <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
              {incidents.data!.items.slice(0, 10).map((i) => (
                <li key={i.id} className="flex items-center gap-2 px-3 py-2">
                  <SeverityChip severity={i.severity} />
                  <Link href={`/o/${orgId}/incidents/${i.key}`} className="min-w-0 flex-1 truncate hover:underline">
                    {i.title}
                  </Link>
                  <span className="shrink-0 text-xs text-fg-subtle">
                    {t(`status.${i.status}`)} · {ago(i.started_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}

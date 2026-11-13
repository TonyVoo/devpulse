"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";

import { TimeSeriesChart } from "@/components/charts/time-series";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Alert, Card, EmptyState } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { SeverityChip } from "@/components/ui/status";
import { api, ApiError, request } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import { type Fmt, makeFmt, makeT, type MessageKey, type T } from "@/lib/i18n/translate";

type Rule = components["schemas"]["AlertRuleOut"];
type RuleIn = components["schemas"]["AlertRuleIn"];
type Preview = components["schemas"]["PreviewOut"];
type Service = components["schemas"]["ServiceOut"];

const ERROR_RATE = "http.server.error_rate";

/** Standard metrics with the aggregation that makes sense by default. */
export const METRICS: { name: string; label: MessageKey; agg: RuleIn["aggregation"]; unit: "ms" | "pct" | "count" | "num" }[] = [
  { name: "http.server.duration_ms", label: "alerts.metrics.latency", agg: "p95", unit: "ms" },
  { name: ERROR_RATE, label: "alerts.metrics.errorRate", agg: "ratio", unit: "pct" },
  { name: "http.server.requests", label: "alerts.metrics.requests", agg: "sum", unit: "count" },
  { name: "process.cpu.utilization", label: "alerts.metrics.cpu", agg: "avg", unit: "pct" },
  { name: "process.memory.usage_bytes", label: "alerts.metrics.memory", agg: "avg", unit: "count" },
  { name: "db.pool.connections_in_use", label: "alerts.metrics.dbPool", agg: "max", unit: "num" },
];
const AGGS: RuleIn["aggregation"][] = ["avg", "p95", "p99", "max", "min", "sum"];
const COMPARATORS: { v: RuleIn["comparator"]; label: string }[] = [
  { v: "gt", label: ">" },
  { v: "gte", label: "≥" },
  { v: "lt", label: "<" },
  { v: "lte", label: "≤" },
];

export function unitFor(metric: string, fmt: Fmt = makeFmt("en")): (v: number) => string {
  const u = METRICS.find((m) => m.name === metric)?.unit ?? "num";
  return fmt[u];
}

/** Turn consecutive breached preview points into shaded ranges. */
export function breachRanges(points: Preview["points"]): { from: number; to: number }[] {
  const out: { from: number; to: number }[] = [];
  let start: number | null = null;
  points.forEach((p, i) => {
    const t = new Date(p.at).getTime();
    if (p.breached && start === null) start = t;
    const next = points[i + 1];
    if (start !== null && (!next || !next.breached)) {
      out.push({ from: start, to: t });
      start = null;
    }
  });
  return out;
}

export function describeRule(
  r: Pick<RuleIn, "metric" | "aggregation" | "comparator" | "threshold" | "window_s" | "for_s">,
  t: T = makeT("en"),
  fmt: Fmt = makeFmt("en"),
): string {
  const cmp = COMPARATORS.find((c) => c.v === r.comparator)?.label ?? r.comparator;
  const agg = r.aggregation === "ratio" ? t("alerts.errorRateAgg") : `${r.aggregation}(${r.metric})`;
  const threshold = unitFor(r.metric, fmt)(r.threshold);
  const hold = r.for_s ? t("alerts.describeHold", { hold: Math.round(r.for_s / 60) }) : "";
  return t("alerts.describe", { agg, window: Math.round(r.window_s / 60), cmp, threshold }) + hold;
}

function useDebounced<T>(value: T, ms: number): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return v;
}


function Builder({
  orgId,
  services,
  rule,
  onDone,
}: {
  orgId: string;
  services: Service[];
  rule?: Rule;
  onDone: () => void;
}) {
  const qc = useQueryClient();
  const { t, fmt } = useI18n();
  const [draft, setDraft] = useState<RuleIn>(
    rule
      ? {
          name: rule.name,
          service_id: rule.service_id,
          metric: rule.metric,
          aggregation: rule.aggregation,
          comparator: rule.comparator,
          threshold: rule.threshold,
          window_s: rule.window_s,
          for_s: rule.for_s,
          severity: rule.severity,
          enabled: rule.enabled,
        }
      : {
          name: "",
          service_id: services[0]?.id ?? "",
          metric: METRICS[0].name,
          aggregation: "p95",
          comparator: "gt",
          threshold: 800,
          window_s: 300,
          for_s: 120,
          severity: "sev2",
          enabled: true,
        },
  );
  const set = (patch: Partial<RuleIn>) => setDraft((d) => ({ ...d, ...patch }));
  const debounced = useDebounced(draft, 500);
  const preview = useQuery({
    queryKey: ["orgs", orgId, "alert-preview", debounced],
    queryFn: () => api.post<Preview>(`orgs/${orgId}/alert-rules/preview?hours=6`, { ...debounced, name: debounced.name || "draft" }),
    enabled: !!debounced.service_id && Number.isFinite(debounced.threshold),
    placeholderData: (prev) => prev,
    retry: false,
  });
  const save = useMutation({
    mutationFn: () =>
      rule
        ? request<Rule>(`/api/v1/orgs/${orgId}/alert-rules/${rule.id}`, {
            method: "PATCH",
            json: { ...draft, service_id: undefined },
            headers: { "If-Match": `"${rule.version}"` },
          })
        : api.post<Rule>(`orgs/${orgId}/alert-rules`, draft),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["orgs", orgId, "alert-rules"] });
      onDone();
    },
  });
  const format = unitFor(draft.metric, fmt);
  const isRate = draft.metric === ERROR_RATE;
  const points = (preview.data?.points ?? []).map((p) => ({ t: new Date(p.at).getTime(), v: p.value }));
  const conflict = save.error instanceof ApiError && save.error.status === 409;

  return (
    <Card className="space-y-5">
      <h2 className="font-semibold">{rule ? t("alerts.editTitle", { name: rule.name }) : t("alerts.new")}</h2>
      <form method="post"
        className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
        onSubmit={(e) => {
          e.preventDefault();
          save.mutate();
        }}
      >
        <Field
          label={t("common.name")}
          value={draft.name}
          onChange={(e) => set({ name: e.target.value })}
          required
          placeholder={t("alerts.namePlaceholder")}
        />
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          {t("common.service")}
          <Select
            value={draft.service_id}
            disabled={!!rule}
            onChange={(e) => set({ service_id: e.target.value })}
            
          >
            {services.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} ({s.environment})
              </option>
            ))}
          </Select>
        </label>
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          {t("alerts.metric")}
          <Select
            value={draft.metric}
            onChange={(e) => {
              const m = METRICS.find((x) => x.name === e.target.value)!;
              set({ metric: m.name, aggregation: m.agg, threshold: m.unit === "pct" ? 0.05 : draft.threshold });
            }}
            
          >
            {METRICS.map((m) => (
              <option key={m.name} value={m.name}>
                {t(m.label)}
              </option>
            ))}
          </Select>
        </label>
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          {t("alerts.aggregation")}
          <Select
            value={draft.aggregation}
            disabled={isRate}
            onChange={(e) => set({ aggregation: e.target.value as RuleIn["aggregation"] })}
            
          >
            {isRate ? <option value="ratio">{t("alerts.ratio")}</option> : AGGS.map((a) => <option key={a}>{a}</option>)}
          </Select>
        </label>
        <div className="flex min-w-0 gap-2">
          <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
            {t("alerts.when")}
            <Select
              value={draft.comparator}
              onChange={(e) => set({ comparator: e.target.value as RuleIn["comparator"] })}
              className="w-20"
            >
              {COMPARATORS.map((c) => (
                <option key={c.v} value={c.v}>
                  {c.label}
                </option>
              ))}
            </Select>
          </label>
          <div className="min-w-0 flex-1">
            <Field
              label={isRate ? t("alerts.thresholdRate") : t("alerts.threshold")}
              type="number"
              step="any"
              value={Number.isFinite(draft.threshold) ? draft.threshold : ""}
              onChange={(e) => set({ threshold: e.target.valueAsNumber })}
              required
            />
          </div>
        </div>
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          {t("alerts.severity")}
          <Select
            value={draft.severity}
            onChange={(e) => set({ severity: e.target.value as RuleIn["severity"] })}
            
          >
            <option value="sev1">{t("alerts.sev1")}</option>
            <option value="sev2">{t("alerts.sev2")}</option>
            <option value="sev3">{t("alerts.sev3")}</option>
            <option value="sev4">{t("alerts.sev4")}</option>
          </Select>
        </label>
        <Field
          label={t("alerts.window")}
          type="number"
          min={1}
          max={60}
          value={draft.window_s / 60}
          onChange={(e) => set({ window_s: Math.round(e.target.valueAsNumber * 60) || 60 })}
        />
        <Field
          label={t("alerts.hold")}
          type="number"
          min={0}
          max={60}
          value={draft.for_s / 60}
          onChange={(e) => set({ for_s: Math.round((e.target.valueAsNumber || 0) * 60) })}
          hint={t("alerts.holdHint")}
        />
        <label className="flex items-center gap-2 self-end pb-2 text-sm">
          <input type="checkbox" checked={draft.enabled} onChange={(e) => set({ enabled: e.target.checked })} />
          {t("alerts.enabled")}
        </label>

        <div className="space-y-2 sm:col-span-2 lg:col-span-3">
          <p className="text-sm text-fg-muted">{describeRule(draft, t, fmt)}</p>
          <TimeSeriesChart
            title={t("alerts.previewTitle")}
            points={points}
            format={format}
            threshold={Number.isFinite(draft.threshold) ? draft.threshold : undefined}
            breaches={breachRanges(preview.data?.points ?? [])}
            domain={points.length ? [points[0].t, points[points.length - 1].t] : undefined}
            loading={preview.isPending}
          />
          <p className="text-sm" aria-live="polite">
            {preview.isError
              ? errorText(preview.error, t)
              : preview.data
                ? preview.data.breach_windows === 0
                  ? t("alerts.wouldNotFire")
                  : (preview.data.breach_windows === 1
                      ? t("alerts.wouldBreachOne")
                      : t("alerts.wouldBreachMany", { n: preview.data.breach_windows })) +
                    (draft.for_s ? t("alerts.beforeHold") : ".")
                : preview.isFetching
                  ? t("alerts.calculating")
                  : ""}
          </p>
        </div>

        {save.isError && (
          <Alert className="sm:col-span-2 lg:col-span-3">
            {conflict ? t("alerts.conflict") : errorText(save.error, t)}
          </Alert>
        )}
        <div className="flex gap-2 sm:col-span-2 lg:col-span-3">
          <Button type="submit" loading={save.isPending}>
            {rule ? t("alerts.saveChanges") : t("alerts.createRule")}
          </Button>
          <Button type="button" variant="ghost" onClick={onDone}>
            {t("common.cancel")}
          </Button>
        </div>
      </form>
    </Card>
  );
}

export function AlertRulesView({ orgId, canManage }: { orgId: string; canManage: boolean }) {
  const qc = useQueryClient();
  const { t, fmt } = useI18n();
  const [editing, setEditing] = useState<Rule | "new" | null>(null);
  const rules = useQuery({
    queryKey: ["orgs", orgId, "alert-rules"],
    queryFn: () => api.get<Rule[]>(`orgs/${orgId}/alert-rules`),
    refetchInterval: 30_000,
  });
  const services = useQuery({
    queryKey: ["orgs", orgId, "services"],
    queryFn: () => api.get<{ items: Service[] }>(`orgs/${orgId}/services?limit=200`),
  });
  const byId = useMemo(() => new Map((services.data?.items ?? []).map((s) => [s.id, s])), [services.data]);
  const toggle = useMutation({
    mutationFn: (r: Rule) =>
      request(`/api/v1/orgs/${orgId}/alert-rules/${r.id}`, {
        method: "PATCH",
        json: { enabled: !r.enabled },
        headers: { "If-Match": `"${r.version}"` },
      }),
    onSettled: () => qc.invalidateQueries({ queryKey: ["orgs", orgId, "alert-rules"] }),
  });
  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`orgs/${orgId}/alert-rules/${id}`),
    onSettled: () => qc.invalidateQueries({ queryKey: ["orgs", orgId, "alert-rules"] }),
  });

  if (rules.isPending || services.isPending) {
    return <div className="h-40 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("alerts.loading")} />;
  }
  if (rules.isError || services.isError) {
    return (
      <Alert>
        {t("alerts.loadError")}{" "}
        <Button variant="ghost" size="sm" onClick={() => void rules.refetch()}>{t("common.retry")}</Button>
      </Alert>
    );
  }
  const svcList = services.data.items;
  return (
    <div className="space-y-6">
      {canManage && editing === null && (
        <Button onClick={() => setEditing("new")} disabled={svcList.length === 0}>
          {t("alerts.new")}
        </Button>
      )}
      {canManage && svcList.length === 0 && <Alert tone="info">{t("alerts.needService")}</Alert>}
      {editing !== null && (
        <Builder
          key={editing === "new" ? "new" : editing.id}
          orgId={orgId}
          services={svcList}
          rule={editing === "new" ? undefined : editing}
          onDone={() => setEditing(null)}
        />
      )}
      {(toggle.error ?? remove.error) && <Alert>{errorText(toggle.error ?? remove.error, t)}</Alert>}
      {rules.data.length === 0 ? (
        <EmptyState title={t("alerts.emptyTitle")} description={t("alerts.emptyBody")} />
      ) : (
        <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
          {rules.data.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm">
              <SeverityChip severity={r.severity} />
              <div className="min-w-[12rem] flex-1">
                <div className="font-medium">
                  {r.name}
                  {r.state === "firing" && <span className="ml-2 text-xs font-semibold text-critical">{t("alerts.firing")}</span>}
                  {r.state === "pending" && <span className="ml-2 text-xs font-semibold text-degraded">{t("alerts.pending")}</span>}
                  {!r.enabled && <span className="ml-2 text-xs text-fg-subtle">{t("alerts.disabled")}</span>}
                </div>
                <div className="text-xs text-fg-subtle">
                  {byId.get(r.service_id)?.name ?? t("alerts.unknownService")} · {describeRule(r, t, fmt)}
                </div>
              </div>
              {canManage && (
                <div className="flex gap-1">
                  <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>
                    {t("common.edit")}
                  </Button>
                  <Button size="sm" variant="ghost" loading={toggle.isPending && toggle.variables?.id === r.id} onClick={() => toggle.mutate(r)}>
                    {r.enabled ? t("alerts.disable") : t("alerts.enable")}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (window.confirm(t("alerts.confirmDelete", { name: r.name }))) remove.mutate(r.id);
                    }}
                  >
                    {t("common.delete")}
                  </Button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

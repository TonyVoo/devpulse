"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Alert, Card } from "@/components/ui/card";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Settings = components["schemas"]["AISettingsOut"];
type SettingsIn = components["schemas"]["AISettingsIn"];
type Usage = components["schemas"]["UsageOut"];

/** 1 micro = $0.000001. */
export function dollars(micros: number): string {
  const usd = micros / 1_000_000;
  return usd < 0.01 && usd > 0 ? `$${usd.toFixed(4)}` : `$${usd.toFixed(2)}`;
}

const PROVIDER_LABEL: Record<string, string> = {
  gemini: "Google Gemini",
  anthropic: "Anthropic (Claude)",
  fake: "Demo analyzer (rule-based, not an LLM)",
};

function SettingsForm({ orgId, s }: { orgId: string; s: Settings }) {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    enabled: s.enabled,
    provider: s.provider ?? "",
    model: s.model ?? "",
    budget: String(s.monthly_budget_micros / 1_000_000),
    auto: s.auto_investigate_min_severity ?? "",
    redaction: s.data_redaction ?? { emails: true, ips: true, secrets: true },
  });
  const save = useMutation({
    mutationFn: () =>
      api.put<Settings>(`orgs/${orgId}/ai/settings`, {
        enabled: form.enabled,
        provider: form.provider || null,
        model: form.model.trim() || null,
        monthly_budget_micros: Math.round(Number(form.budget) * 1_000_000),
        max_tokens_per_run: s.max_tokens_per_run,
        auto_investigate_min_severity: (form.auto || null) as SettingsIn["auto_investigate_min_severity"],
        data_redaction: form.redaction,
      } satisfies SettingsIn),
    onSuccess: (data) => qc.setQueryData(["orgs", orgId, "ai-settings"], data),
  });
  const providerName = form.provider || s.effective_provider;
  const configured = s.providers.find((p) => p.name === providerName)?.configured ?? false;

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        save.mutate();
      }}
    >
      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={form.enabled}
          onChange={(e) => setForm({ ...form, enabled: e.target.checked })}
        />
        Enable AI analysis for this organization
      </label>
      <p className="text-xs text-fg-subtle">
        When enabled, incident metrics, logs (redacted), deployments and past incidents are sent to the selected
        provider. Nothing is sent while this is off.
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          Provider
          <select
            value={form.provider}
            onChange={(e) => setForm({ ...form, provider: e.target.value })}
            className="min-h-10 w-full min-w-0 rounded-md border border-line bg-canvas px-2"
          >
            <option value="">Server default ({PROVIDER_LABEL[s.effective_provider] ?? s.effective_provider})</option>
            {s.providers.map((p) => (
              <option key={p.name} value={p.name} disabled={!p.configured}>
                {PROVIDER_LABEL[p.name] ?? p.name}
                {!p.configured && " — not configured on this server"}
              </option>
            ))}
          </select>
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          Model
          <input
            value={form.model}
            onChange={(e) => setForm({ ...form, model: e.target.value })}
            placeholder={s.effective_model}
            className="min-h-10 w-full min-w-0 rounded-md border border-line bg-canvas px-3"
          />
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          Monthly budget (USD)
          <input
            type="number"
            min={0}
            step="0.01"
            value={form.budget}
            onChange={(e) => setForm({ ...form, budget: e.target.value })}
            className="min-h-10 w-full min-w-0 rounded-md border border-line bg-canvas px-3"
          />
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          Investigate automatically
          <select
            value={form.auto}
            onChange={(e) => setForm({ ...form, auto: e.target.value })}
            className="min-h-10 w-full min-w-0 rounded-md border border-line bg-canvas px-2"
          >
            <option value="">Never (manual only)</option>
            <option value="sev1">SEV1 incidents</option>
            <option value="sev2">SEV2 and above</option>
            <option value="sev3">SEV3 and above</option>
            <option value="sev4">All incidents</option>
          </select>
        </label>
      </div>
      <fieldset className="space-y-1 text-sm">
        <legend className="mb-1 font-medium">Redact before sending</legend>
        {(["emails", "ips", "secrets"] as const).map((k) => (
          <label key={k} className="mr-4 inline-flex items-center gap-2">
            <input
              type="checkbox"
              checked={form.redaction[k] ?? true}
              onChange={(e) => setForm({ ...form, redaction: { ...form.redaction, [k]: e.target.checked } })}
            />
            {k === "ips" ? "IP addresses" : k === "secrets" ? "Tokens and secrets" : "Email addresses"}
          </label>
        ))}
      </fieldset>
      {providerName === "gemini" && (
        <Alert tone="info">
          On the Gemini API free tier, Google may use the data sent (incident metrics, redacted logs, deployments) to
          improve its products. Use a paid Gemini key if that isn&apos;t acceptable for your organization.
        </Alert>
      )}
      {form.enabled && !configured && (
        <Alert>The selected provider isn&apos;t configured on this server; enabling will be refused.</Alert>
      )}
      {save.isError && (
        <Alert>{save.error instanceof ApiError ? save.error.problem.detail : save.error.message}</Alert>
      )}
      {save.isSuccess && <Alert tone="info">Saved.</Alert>}
      <Button type="submit" loading={save.isPending}>Save</Button>
    </form>
  );
}

export function AiSettingsView({ orgId, canConfigure }: { orgId: string; canConfigure: boolean }) {
  const settings = useQuery({
    queryKey: ["orgs", orgId, "ai-settings"],
    queryFn: () => api.get<Settings>(`orgs/${orgId}/ai/settings`),
  });
  const usage = useQuery({
    queryKey: ["orgs", orgId, "ai-usage"],
    queryFn: () => api.get<Usage>(`orgs/${orgId}/ai/usage`),
    enabled: canConfigure,
  });

  if (settings.isPending) return <div className="h-40 animate-pulse rounded-md bg-surface" role="status" aria-busy aria-label="Loading AI settings" />;
  if (settings.isError) return <Alert>Couldn&apos;t load AI settings: {settings.error.message}</Alert>;
  const s = settings.data;
  const pct = s.monthly_budget_micros > 0 ? Math.min(100, (s.month_to_date_cost_micros / s.monthly_budget_micros) * 100) : 100;

  return (
    <div className="grid min-w-0 gap-6 lg:grid-cols-2">
      <Card className="min-w-0 space-y-4">
        <h2 className="font-semibold">Settings</h2>
        {canConfigure ? (
          <SettingsForm orgId={orgId} s={s} />
        ) : (
          <dl className="grid grid-cols-2 gap-2 text-sm">
            <dt className="text-fg-subtle">Status</dt>
            <dd>{s.enabled ? "Enabled" : "Off"}</dd>
            <dt className="text-fg-subtle">Provider</dt>
            <dd>{PROVIDER_LABEL[s.effective_provider] ?? s.effective_provider}</dd>
            <dt className="text-fg-subtle">Model</dt>
            <dd className="font-mono text-xs">{s.effective_model}</dd>
            <dd className="col-span-2 text-xs text-fg-subtle">Only admins can change these settings.</dd>
          </dl>
        )}
      </Card>
      <Card className="min-w-0 space-y-4">
        <h2 className="font-semibold">This month</h2>
        <div>
          <div className="flex justify-between text-sm">
            <span>{dollars(s.month_to_date_cost_micros)} spent</span>
            <span className="text-fg-subtle">of {dollars(s.monthly_budget_micros)}</span>
          </div>
          <div
            className="mt-1 h-2 rounded bg-raised"
            role="meter"
            aria-label="Budget used"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={Math.round(pct)}
          >
            <div className={pct >= 90 ? "h-2 rounded bg-critical" : "h-2 rounded bg-cyan"} style={{ width: `${pct}%` }} />
          </div>
        </div>
        {canConfigure &&
          (usage.isPending ? null : usage.isError ? (
            <Alert>Couldn&apos;t load usage.</Alert>
          ) : usage.data.days.length === 0 ? (
            <p className="text-sm text-fg-subtle">No AI calls yet this month.</p>
          ) : (
            <div className="overflow-x-auto"><table className="w-full text-left text-xs">
              <thead className="text-fg-subtle">
                <tr>
                  <th className="py-1 font-medium">Day</th>
                  <th className="font-medium">Model</th>
                  <th className="text-right font-medium">Calls</th>
                  <th className="text-right font-medium">Tokens in / out</th>
                  <th className="text-right font-medium">Cost</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {usage.data.days.map((d) => (
                  <tr key={`${d.day}-${d.model}`}>
                    <td className="py-1">{d.day}</td>
                    <td className="font-mono">{d.model}</td>
                    <td className="text-right">{d.calls}</td>
                    <td className="text-right">
                      {d.input_tokens.toLocaleString()} / {d.output_tokens.toLocaleString()}
                    </td>
                    <td className="text-right">{dollars(d.cost_micros)}</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          ))}
      </Card>
    </div>
  );
}

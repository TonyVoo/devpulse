"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Alert, Card } from "@/components/ui/card";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { type Locale, LOCALE_NAME, LOCALES } from "@/lib/i18n/config";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import type { T } from "@/lib/i18n/translate";

type Settings = components["schemas"]["AISettingsOut"];
type SettingsIn = components["schemas"]["AISettingsIn"];
type Usage = components["schemas"]["UsageOut"];

/** 1 micro = $0.000001. */
export function dollars(micros: number): string {
  const usd = micros / 1_000_000;
  return usd < 0.01 && usd > 0 ? `$${usd.toFixed(4)}` : `$${usd.toFixed(2)}`;
}

function providerLabel(name: string, t: T): string {
  if (name === "gemini") return "Google Gemini";
  if (name === "anthropic") return "Anthropic (Claude)";
  if (name === "fake") return t("ai.settings.demoProvider");
  return name;
}

function SettingsForm({ orgId, s }: { orgId: string; s: Settings }) {
  const qc = useQueryClient();
  const { t } = useI18n();
  const [form, setForm] = useState({
    enabled: s.enabled,
    provider: s.provider ?? "",
    model: s.model ?? "",
    budget: String(s.monthly_budget_micros / 1_000_000),
    auto: s.auto_investigate_min_severity ?? "",
    redaction: s.data_redaction ?? { emails: true, ips: true, secrets: true },
    language: s.language,
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
        language: form.language,
      } satisfies SettingsIn),
    onSuccess: (data) => qc.setQueryData(["orgs", orgId, "ai-settings"], data),
  });
  const providerName = form.provider || s.effective_provider;
  const configured = s.providers.find((p) => p.name === providerName)?.configured ?? false;

  return (
    <form method="post"
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
        {t("ai.settings.enable")}
      </label>
      <p className="text-xs text-fg-subtle">{t("ai.settings.enableHint")}</p>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          {t("ai.settings.provider")}
          <Select
            value={form.provider}
            onChange={(e) => setForm({ ...form, provider: e.target.value })}
            
          >
            <option value="">{t("ai.settings.serverDefault", { provider: providerLabel(s.effective_provider, t) })}</option>
            {s.providers.map((p) => (
              <option key={p.name} value={p.name} disabled={!p.configured}>
                {providerLabel(p.name, t)}
                {!p.configured && t("ai.settings.notConfigured")}
              </option>
            ))}
          </Select>
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          {t("ai.settings.model")}
          <input
            value={form.model}
            onChange={(e) => setForm({ ...form, model: e.target.value })}
            placeholder={s.effective_model}
            
          />
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          {t("ai.settings.budget")}
          <input
            type="number"
            min={0}
            step="0.01"
            value={form.budget}
            onChange={(e) => setForm({ ...form, budget: e.target.value })}
            
          />
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          {t("ai.settings.auto")}
          <Select
            value={form.auto}
            onChange={(e) => setForm({ ...form, auto: e.target.value })}
            
          >
            <option value="">{t("ai.settings.autoNever")}</option>
            <option value="sev1">{t("ai.settings.autoSev1")}</option>
            <option value="sev2">{t("ai.settings.autoSev2")}</option>
            <option value="sev3">{t("ai.settings.autoSev3")}</option>
            <option value="sev4">{t("ai.settings.autoAll")}</option>
          </Select>
        </label>
        <label className="flex min-w-0 flex-col gap-1 text-sm">
          {t("ai.settings.language")}
          <Select
            value={form.language}
            onChange={(e) => setForm({ ...form, language: e.target.value as Locale })}
          >
            {LOCALES.map((l) => (
              <option key={l} value={l}>
                {LOCALE_NAME[l]}
              </option>
            ))}
          </Select>
          <span className="text-xs text-fg-subtle">{t("ai.settings.languageHint")}</span>
        </label>
      </div>
      <fieldset className="space-y-1 text-sm">
        <legend className="mb-1 font-medium">{t("ai.settings.redact")}</legend>
        {(["emails", "ips", "secrets"] as const).map((k) => (
          <label key={k} className="mr-4 inline-flex items-center gap-2">
            <input
              type="checkbox"
              checked={form.redaction[k] ?? true}
              onChange={(e) => setForm({ ...form, redaction: { ...form.redaction, [k]: e.target.checked } })}
            />
            {t(k === "ips" ? "ai.settings.redactIps" : k === "secrets" ? "ai.settings.redactSecrets" : "ai.settings.redactEmails")}
          </label>
        ))}
      </fieldset>
      {providerName === "gemini" && (
        <Alert tone="info">{t("ai.settings.geminiWarning")}</Alert>
      )}
      {form.enabled && !configured && (
        <Alert>{t("ai.settings.providerMissing")}</Alert>
      )}
      {save.isError && (
        <Alert>{errorText(save.error, t)}</Alert>
      )}
      {save.isSuccess && <Alert tone="info">{t("common.saved")}</Alert>}
      <Button type="submit" loading={save.isPending}>{t("common.save")}</Button>
    </form>
  );
}

export function AiSettingsView({ orgId, canConfigure }: { orgId: string; canConfigure: boolean }) {
  const { t, fmt } = useI18n();
  const settings = useQuery({
    queryKey: ["orgs", orgId, "ai-settings"],
    queryFn: () => api.get<Settings>(`orgs/${orgId}/ai/settings`),
  });
  const usage = useQuery({
    queryKey: ["orgs", orgId, "ai-usage"],
    queryFn: () => api.get<Usage>(`orgs/${orgId}/ai/usage`),
    enabled: canConfigure,
  });

  if (settings.isPending) return <div className="h-40 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("ai.settings.loading")} />;
  if (settings.isError) return <Alert>{t("ai.settings.loadError", { error: errorText(settings.error, t) })}</Alert>;
  const s = settings.data;
  const pct = s.monthly_budget_micros > 0 ? Math.min(100, (s.month_to_date_cost_micros / s.monthly_budget_micros) * 100) : 100;

  return (
    <div className="grid min-w-0 gap-6 lg:grid-cols-2">
      <Card className="min-w-0 space-y-4">
        <h2 className="font-semibold">{t("ai.settings.heading")}</h2>
        {canConfigure ? (
          <SettingsForm orgId={orgId} s={s} />
        ) : (
          <dl className="grid grid-cols-2 gap-2 text-sm">
            <dt className="text-fg-subtle">{t("ai.settings.status")}</dt>
            <dd>{s.enabled ? t("ai.settings.enabled") : t("ai.settings.off")}</dd>
            <dt className="text-fg-subtle">{t("ai.settings.provider")}</dt>
            <dd>{providerLabel(s.effective_provider, t)}</dd>
            <dt className="text-fg-subtle">{t("ai.settings.model")}</dt>
            <dd className="font-mono text-xs">{s.effective_model}</dd>
            <dd className="col-span-2 text-xs text-fg-subtle">{t("ai.settings.adminsOnly")}</dd>
          </dl>
        )}
      </Card>
      <Card className="min-w-0 space-y-4">
        <h2 className="font-semibold">{t("ai.settings.thisMonth")}</h2>
        <div>
          <div className="flex justify-between text-sm">
            <span>{t("ai.settings.spent", { amount: dollars(s.month_to_date_cost_micros) })}</span>
            <span className="text-fg-subtle">{t("ai.settings.of", { amount: dollars(s.monthly_budget_micros) })}</span>
          </div>
          <div
            className="mt-1 h-2 rounded bg-raised"
            role="meter"
            aria-label={t("ai.settings.budgetUsed")}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={Math.round(pct)}
          >
            <div className={pct >= 90 ? "h-2 rounded bg-critical" : "h-2 rounded bg-cyan"} style={{ width: `${pct}%` }} />
          </div>
        </div>
        {canConfigure &&
          (usage.isPending ? null : usage.isError ? (
            <Alert>{t("ai.settings.usageError")}</Alert>
          ) : usage.data.days.length === 0 ? (
            <p className="text-sm text-fg-subtle">{t("ai.settings.noCalls")}</p>
          ) : (
            <div className="overflow-x-auto"><table className="w-full text-left text-xs">
              <thead className="text-fg-subtle">
                <tr>
                  <th className="py-1 font-medium">{t("ai.settings.day")}</th>
                  <th className="font-medium">{t("ai.settings.model")}</th>
                  <th className="text-right font-medium">{t("ai.settings.calls")}</th>
                  <th className="text-right font-medium">{t("ai.settings.tokens")}</th>
                  <th className="text-right font-medium">{t("ai.settings.cost")}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {usage.data.days.map((d) => (
                  <tr key={`${d.day}-${d.model}`}>
                    <td className="py-1">{d.day}</td>
                    <td className="font-mono">{d.model}</td>
                    <td className="text-right">{d.calls}</td>
                    <td className="text-right">
                      {fmt.int(d.input_tokens)} / {fmt.int(d.output_tokens)}
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

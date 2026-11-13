"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";
import { makeT, type MessageKey, type T } from "@/lib/i18n/translate";
import { cn } from "@/lib/utils";

export type Investigation = components["schemas"]["InvestigationOut"];
type Summary = components["schemas"]["InvestigationSummary"];
type Evidence = components["schemas"]["EvidenceOut"];
type Message = components["schemas"]["MessageOut"];
type AskOut = components["schemas"]["AskOut"];
type Cause = components["schemas"]["Cause"];

const ACTIVE = new Set(["queued", "collecting", "analyzing"]);

const PROGRESS: Record<string, MessageKey> = {
  queued: "ai.progress.queued",
  collecting: "ai.progress.collecting",
  analyzing: "ai.progress.analyzing",
};

/** Plain-language explanation for a stable AI error code. */
export function aiErrorMessage(code: string | null | undefined, detail?: string | null, t: T = makeT("en")): string {
  switch (code) {
    case "ai.disabled":
    case "ai.budget_exceeded":
    case "ai.provider_unconfigured":
    case "ai.no_evidence":
    case "ai.invalid_output":
    case "ai.refused":
    case "ai.already_running":
    case "ai.stale":
      return t(`ai.errors.${code}`);
    case "ai.run_timeout":
    case "ai.timeout":
      return t("ai.errors.timeout");
    case "ai.rate_limited":
    case "ai.provider_unavailable":
    case "ai.provider_unreachable":
      return t("ai.errors.unavailable");
    default:
      return detail || t("ai.errors.failed");
  }
}

const RISK: Record<string, { label: MessageKey; className: string }> = {
  read_only: { label: "ai.risk.read_only", className: "text-healthy" },
  sensitive: { label: "ai.risk.sensitive", className: "text-degraded" },
  destructive: { label: "ai.risk.destructive", className: "text-critical" },
};

const CONFIDENCE: Record<string, string> = {
  high: "bg-cyan/15 text-cyan",
  medium: "bg-degraded/15 text-degraded",
  low: "bg-raised text-fg-subtle",
};

export function DemoAnalyzerTag() {
  const { t } = useI18n();
  return (
    <span className="rounded bg-violet/15 px-1.5 py-px text-[10px] font-bold tracking-wide text-violet">
      {t("ai.demoTag")}
    </span>
  );
}

function EvidenceRef({ ev, refId, counter }: { ev?: Evidence; refId: string; counter?: boolean }) {
  const [open, setOpen] = useState(false);
  const { t } = useI18n();
  if (!ev) return <span className="font-mono text-xs text-fg-subtle">{refId}</span>;
  const q = ev.source_query as Record<string, unknown>;
  return (
    <span className="inline-block">
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "rounded border px-1.5 py-px font-mono text-xs hover:bg-raised",
          counter ? "border-degraded/50 text-degraded" : "border-line text-fg",
        )}
        title={ev.title}
      >
        {refId}
        {counter && t("ai.against")}
      </button>
      {open && (
        <span className="mt-1 block rounded-md border border-line bg-canvas p-3 text-xs">
          <span className="block font-medium">{ev.title}</span>
          <span className="mt-1 block">{String((ev.excerpt as Record<string, unknown>).text ?? "")}</span>
          <span className="mt-1 block text-fg-subtle">
            {t("ai.evidenceSource", {
              kind: ev.kind,
              source: `${String(q.type ?? "")}${q.name ? ` ${String(q.name)}` : ""}`,
            })}
          </span>
        </span>
      )}
    </span>
  );
}

function CauseView({ cause, rank, inv }: { cause: Cause; rank: number; inv: Investigation }) {
  const { t } = useI18n();
  const byRef = new Map(inv.evidence.map((e) => [e.ref, e]));
  const level = cause.confidence_label as "high" | "medium" | "low";
  const pct = Math.round(cause.confidence * 100);
  return (
    <li className="space-y-1">
      <div className="flex items-start justify-between gap-3">
        <span className="font-medium">
          {rank}. {cause.cause}
        </span>
        <span
          className={cn("shrink-0 rounded px-1.5 py-px text-[11px] font-bold", CONFIDENCE[cause.confidence_label])}
          aria-label={t("ai.confidence", { label: t(`ai.confidenceWord.${level}`), pct })}
        >
          {t(`ai.confidenceLabel.${level}`)} · {pct}%
        </span>
      </div>
      <p className="text-sm text-fg-muted">{cause.reasoning}</p>
      <div className="flex flex-wrap gap-1.5">
        {cause.evidence_refs.map((r) => (
          <EvidenceRef key={r} refId={r} ev={byRef.get(r)} />
        ))}
        {cause.counter_evidence_refs.map((r) => (
          <EvidenceRef key={`c-${r}`} refId={r} ev={byRef.get(r)} counter />
        ))}
      </div>
      {cause.how_to_verify && <p className="text-xs text-fg-subtle">{t("ai.verify", { how: cause.how_to_verify })}</p>}
    </li>
  );
}

export function AnalysisView({
  inv,
  canAct,
  isAdmin,
  onDecide,
  deciding,
}: {
  inv: Investigation;
  canAct: boolean;
  isAdmin: boolean;
  onDecide: (proposalId: string, approve: boolean) => void;
  deciding?: string | null;
}) {
  const { t, ago } = useI18n();
  const a = inv.result!;
  const proposals = new Map(inv.proposals.map((p) => [p.id, p]));
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2 text-xs text-fg-subtle">
        <span>{t("ai.hypotheses", { ago: ago(inv.created_at) })}</span>
        {inv.is_demo_provider ? <DemoAnalyzerTag /> : <span className="font-mono">{inv.model}</span>}
      </div>
      <div>
        <p className="text-lg font-medium">{a.summary}</p>
        {a.impact && <p className="mt-1 text-sm text-fg-muted">{a.impact}</p>}
      </div>
      <section aria-labelledby="causes">
        <h3 id="causes" className="mb-2 text-sm font-semibold">{t("ai.causes")}</h3>
        <ol className="space-y-4">
          {a.probable_causes.map((c, i) => (
            <CauseView key={c.cause} cause={c} rank={i + 1} inv={inv} />
          ))}
        </ol>
      </section>
      {a.recommended_actions.length > 0 && (
        <section aria-labelledby="actions">
          <h3 id="actions" className="mb-2 text-sm font-semibold">{t("ai.nextSteps")}</h3>
          <ul className="space-y-3">
            {a.recommended_actions.map((act) => {
              const p = act.proposal_id ? proposals.get(act.proposal_id) : undefined;
              const risk = RISK[act.risk];
              const mayDecide = canAct && p?.status === "proposed" && (act.risk !== "destructive" || isAdmin);
              return (
                <li key={act.action} className="text-sm">
                  <div>{act.action}</div>
                  <div className="flex flex-wrap items-center gap-2 text-xs">
                    <span className={risk.className}>{t(risk.label)}</span>
                    {p && p.status !== "proposed" && (
                      <span className="text-fg-subtle">
                        · {p.status === "approved" ? t("ai.approvedNotRun") : t("ai.rejected")}
                      </span>
                    )}
                    {p?.status === "proposed" && act.risk === "destructive" && !isAdmin && (
                      <span className="text-fg-subtle">· {t("ai.adminMustDecide")}</span>
                    )}
                  </div>
                  {mayDecide && (
                    <div className="mt-1 flex gap-2">
                      <Button
                        size="sm"
                        variant="secondary"
                        loading={deciding === p.id}
                        onClick={() => {
                          if (window.confirm(t("ai.confirmApprove", { description: p.description })))
                            onDecide(p.id, true);
                        }}
                      >
                        {t("ai.approve")}
                      </Button>
                      <Button size="sm" variant="ghost" disabled={deciding === p.id} onClick={() => onDecide(p.id, false)}>
                        {t("ai.reject")}
                      </Button>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}
      {a.data_gaps.length > 0 && (
        <section aria-labelledby="gaps">
          <h3 id="gaps" className="mb-1 text-sm font-semibold">{t("ai.gaps")}</h3>
          <ul className="list-disc space-y-0.5 pl-5 text-xs text-fg-muted">
            {a.data_gaps.map((g) => (
              <li key={g}>{g}</li>
            ))}
          </ul>
        </section>
      )}
      {(a.adjustments ?? []).map((adj) => (
        <p key={adj} className="text-xs text-fg-subtle">{t("ai.adjusted", { text: adj })}</p>
      ))}
      {a.limitations && <p className="text-xs italic text-fg-subtle">{a.limitations}</p>}
    </div>
  );
}

function Chat({ orgId, inv, canAct }: { orgId: string; inv: Investigation; canAct: boolean }) {
  const qc = useQueryClient();
  const { t, locale } = useI18n();
  const [question, setQuestion] = useState("");
  const [clientId, setClientId] = useState<string | null>(null);
  const messages = useQuery({
    queryKey: ["orgs", orgId, "ai", inv.id, "messages"],
    queryFn: () => api.get<Message[]>(`orgs/${orgId}/ai/investigations/${inv.id}/messages`),
  });
  const ask = useMutation({
    mutationFn: (vars: { question: string; clientId: string }) =>
      api.post<AskOut>(`orgs/${orgId}/ai/investigations/${inv.id}/messages`, {
        question: vars.question,
        client_id: vars.clientId,
        language: locale, // answers come back in the asker's language
      }),
    onSuccess: () => {
      setQuestion("");
      setClientId(null);
      qc.invalidateQueries({ queryKey: ["orgs", orgId, "ai", inv.id] });
      qc.invalidateQueries({ queryKey: ["orgs", orgId, "incident-ai"] });
    },
    onError: (e) => {
      // The server answered (validation, provider error): the next try is a new question.
      if (e instanceof ApiError && e.status !== 0) setClientId(null);
    },
  });
  const byRef = new Map(inv.evidence.map((e) => [e.ref, e]));
  const visible = (messages.data ?? []).filter((m) => m.role !== "tool" || m.evidence_refs.length > 0);

  return (
    <section aria-labelledby="ask" className="space-y-3 border-t border-line pt-4">
      <h3 id="ask" className="text-sm font-semibold">{t("ai.ask")}</h3>
      {visible.length === 0 && !ask.isPending && (
        <p className="text-xs text-fg-subtle">{t("ai.askHint")}</p>
      )}
      <ul className="space-y-2">
        {visible.map((m) => (
          <li
            key={m.id}
            className={cn(
              "rounded-md p-3 text-sm",
              m.role === "user" ? "ml-auto max-w-[85%] bg-cyan/10" : m.role === "tool" ? "p-0 text-xs text-fg-subtle" : "bg-raised",
            )}
          >
            {m.role === "tool" ? (
              <>
                {t("ai.lookedUp", { tool: m.tool_name?.replaceAll("_", " ") ?? "", refs: m.evidence_refs.join(", ") })}
              </>
            ) : (
              <>
                <p className="whitespace-pre-wrap">{m.content}</p>
                {m.evidence_refs.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {m.evidence_refs.map((r) => (
                      <EvidenceRef key={r} refId={r} ev={byRef.get(r)} />
                    ))}
                  </div>
                )}
              </>
            )}
          </li>
        ))}
        {ask.isPending && <li className="text-xs text-fg-subtle" aria-live="polite">{t("ai.thinking")}</li>}
      </ul>
      {ask.isError && (
        <Alert>
          {aiErrorMessage(ask.error instanceof ApiError ? ask.error.problem.code : null, errorText(ask.error, t), t)}
        </Alert>
      )}
      {canAct && (
        <form method="post"
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            const q = question.trim();
            if (!q) return;
            // Same client id on retry → the server returns the stored answer, not a second one.
            const id = clientId ?? crypto.randomUUID();
            setClientId(id);
            ask.mutate({ question: q, clientId: id });
          }}
        >
          <label htmlFor="ai-question" className="sr-only">{t("ai.question")}</label>
          <input
            id="ai-question"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            maxLength={2000}
            placeholder={t("ai.questionPlaceholder")}
            className="min-h-10 flex-1 rounded-md border border-line bg-canvas px-3 text-sm"
          />
          <Button type="submit" loading={ask.isPending}>{t("ai.askButton")}</Button>
        </form>
      )}
    </section>
  );
}

/** AI analysis block of the incident page. */
export function AiPanel({
  orgId,
  incidentRef,
  canAct,
  isAdmin,
}: {
  orgId: string;
  incidentRef: string;
  canAct: boolean;
  isAdmin: boolean;
}) {
  const qc = useQueryClient();
  const { t, locale } = useI18n();
  const key = ["orgs", orgId, "incident-ai", incidentRef];
  const latest = useQuery({
    queryKey: key,
    queryFn: async () => {
      const runs = await api.get<Summary[]>(`orgs/${orgId}/incidents/${incidentRef}/investigations`);
      return runs.length ? api.get<Investigation>(`orgs/${orgId}/ai/investigations/${runs[0].id}`) : null;
    },
    refetchInterval: (q) => (q.state.data && ACTIVE.has(q.state.data.status) ? 3000 : 30_000),
  });
  const start = useMutation({
    // The analysis is written in the language of the person who asked for it.
    mutationFn: () =>
      api.post<Investigation>(`orgs/${orgId}/incidents/${incidentRef}/investigations`, { language: locale }),
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });
  const decide = useMutation({
    mutationFn: (v: { invId: string; proposalId: string; approve: boolean }) =>
      api.post(`orgs/${orgId}/ai/investigations/${v.invId}/proposals/${v.proposalId}/decision`, { approve: v.approve }),
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });
  const feedback = useMutation({
    mutationFn: (v: { invId: string; helpful: boolean }) =>
      api.put(`orgs/${orgId}/ai/investigations/${v.invId}/feedback`, { helpful: v.helpful }),
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });

  const inv = latest.data;
  const startError =
    start.error instanceof ApiError ? aiErrorMessage(start.error.problem.code, errorText(start.error, t), t) : null;

  return (
    <section aria-labelledby="ai-analysis" className="rounded-lg border border-line bg-surface p-6">
      <div className="mb-4 flex items-center justify-between gap-2">
        <h2 id="ai-analysis" className="font-semibold">{t("ai.analysis")}</h2>
        {inv && !ACTIVE.has(inv.status) && canAct && (
          <Button size="sm" variant="ghost" loading={start.isPending} onClick={() => start.mutate()}>
            {t("ai.runAgain")}
          </Button>
        )}
      </div>
      {startError && <Alert className="mb-4">{startError}</Alert>}
      {latest.isPending ? (
        <div className="h-24 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label={t("ai.loading")} />
      ) : latest.isError ? (
        <Alert>
          {t("ai.loadError")}{" "}
          <Button variant="ghost" size="sm" onClick={() => latest.refetch()}>{t("common.retry")}</Button>
        </Alert>
      ) : !inv ? (
        <div className="space-y-3">
          <p className="text-sm text-fg-muted">{t("ai.intro2")}</p>
          {canAct && (
            <Button loading={start.isPending} onClick={() => start.mutate()}>
              {t("ai.investigate")}
            </Button>
          )}
        </div>
      ) : ACTIVE.has(inv.status) ? (
        <p className="flex items-center gap-2 text-sm" aria-live="polite">
          <span aria-hidden className="size-3.5 animate-spin rounded-full border-2 border-current border-r-transparent" />
          {t(PROGRESS[inv.status])}
        </p>
      ) : inv.status === "succeeded" && inv.result ? (
        <div className="space-y-5">
          <AnalysisView
            inv={inv}
            canAct={canAct}
            isAdmin={isAdmin}
            deciding={decide.isPending ? decide.variables?.proposalId : null}
            onDecide={(proposalId, approve) => decide.mutate({ invId: inv.id, proposalId, approve })}
          />
          {decide.error && <Alert>{errorText(decide.error, t)}</Alert>}
          <div className="flex items-center gap-2 text-xs text-fg-subtle">
            {t("ai.helpful")}
            <Button
              size="sm"
              variant={inv.my_feedback === true ? "secondary" : "ghost"}
              aria-pressed={inv.my_feedback === true}
              onClick={() => feedback.mutate({ invId: inv.id, helpful: true })}
            >
              {t("common.yes")}
            </Button>
            <Button
              size="sm"
              variant={inv.my_feedback === false ? "secondary" : "ghost"}
              aria-pressed={inv.my_feedback === false}
              onClick={() => feedback.mutate({ invId: inv.id, helpful: false })}
            >
              {t("common.no")}
            </Button>
          </div>
          <Chat orgId={orgId} inv={inv} canAct={canAct} />
        </div>
      ) : (
        <div className="space-y-2">
          <p className="font-medium">{t("ai.unavailable")}</p>
          <p className="text-sm text-fg-muted">{aiErrorMessage(inv.error_code, inv.error_detail, t)}</p>
          <p className="text-xs text-fg-subtle">{t("ai.actionsUnaffected")}</p>
        </div>
      )}
    </section>
  );
}

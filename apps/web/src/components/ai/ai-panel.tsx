"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { timeAgo } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { cn } from "@/lib/utils";

export type Investigation = components["schemas"]["InvestigationOut"];
type Summary = components["schemas"]["InvestigationSummary"];
type Evidence = components["schemas"]["EvidenceOut"];
type Message = components["schemas"]["MessageOut"];
type AskOut = components["schemas"]["AskOut"];
type Cause = components["schemas"]["Cause"];

const ACTIVE = new Set(["queued", "collecting", "analyzing"]);

const PROGRESS: Record<string, string> = {
  queued: "Waiting for a worker…",
  collecting: "Collecting metrics, logs and deployments…",
  analyzing: "Analysing the evidence…",
};

/** Plain-language explanation for a stable AI error code. */
export function aiErrorMessage(code: string | null | undefined, detail?: string | null): string {
  switch (code) {
    case "ai.disabled":
      return "AI analysis is turned off for this organization. An admin can enable it under AI settings.";
    case "ai.budget_exceeded":
      return "This month's AI budget is used up. An admin can raise it under AI settings.";
    case "ai.provider_unconfigured":
      return "No AI provider is configured on this DevPulse server.";
    case "ai.no_evidence":
      return "DevPulse has no telemetry for this incident, so there's nothing to analyse.";
    case "ai.invalid_output":
      return "The AI's answer failed validation and was discarded.";
    case "ai.refused":
      return "The AI model declined to analyse this incident.";
    case "ai.run_timeout":
    case "ai.timeout":
      return "The analysis took too long.";
    case "ai.rate_limited":
    case "ai.provider_unavailable":
    case "ai.provider_unreachable":
      return "The AI provider is unavailable right now. Try again in a minute.";
    case "ai.already_running":
      return "An analysis is already running for this incident.";
    case "ai.stale":
      return "The analysis was interrupted.";
    default:
      return detail || "The analysis failed.";
  }
}

const RISK: Record<string, { label: string; className: string }> = {
  read_only: { label: "Read-only", className: "text-healthy" },
  sensitive: { label: "Changes a system · needs approval", className: "text-degraded" },
  destructive: { label: "Destructive · admin approval", className: "text-critical" },
};

const CONFIDENCE: Record<string, string> = {
  high: "bg-cyan/15 text-cyan",
  medium: "bg-degraded/15 text-degraded",
  low: "bg-raised text-fg-subtle",
};

export function DemoAnalyzerTag() {
  return (
    <span className="rounded bg-violet/15 px-1.5 py-px text-[10px] font-bold tracking-wide text-violet">
      DEMO ANALYZER · NOT AN LLM
    </span>
  );
}

function EvidenceRef({ ev, refId, counter }: { ev?: Evidence; refId: string; counter?: boolean }) {
  const [open, setOpen] = useState(false);
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
        {counter && " (against)"}
      </button>
      {open && (
        <span className="mt-1 block rounded-md border border-line bg-canvas p-3 text-xs">
          <span className="block font-medium">{ev.title}</span>
          <span className="mt-1 block">{String((ev.excerpt as Record<string, unknown>).text ?? "")}</span>
          <span className="mt-1 block text-fg-subtle">
            Computed by DevPulse from stored {ev.kind} data, not by the AI · source: {String(q.type ?? "")}
            {q.name ? ` ${String(q.name)}` : ""}
          </span>
        </span>
      )}
    </span>
  );
}

function CauseView({ cause, rank, inv }: { cause: Cause; rank: number; inv: Investigation }) {
  const byRef = new Map(inv.evidence.map((e) => [e.ref, e]));
  return (
    <li className="space-y-1">
      <div className="flex items-start justify-between gap-3">
        <span className="font-medium">
          {rank}. {cause.cause}
        </span>
        <span
          className={cn("shrink-0 rounded px-1.5 py-px text-[11px] font-bold", CONFIDENCE[cause.confidence_label])}
          aria-label={`${cause.confidence_label} confidence, ${Math.round(cause.confidence * 100)} percent`}
        >
          {cause.confidence_label.toUpperCase()} · {Math.round(cause.confidence * 100)}%
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
      {cause.how_to_verify && <p className="text-xs text-fg-subtle">Verify: {cause.how_to_verify}</p>}
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
  const a = inv.result!;
  const proposals = new Map(inv.proposals.map((p) => [p.id, p]));
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2 text-xs text-fg-subtle">
        <span>Hypotheses — not confirmed · {timeAgo(inv.created_at)}</span>
        {inv.is_demo_provider ? <DemoAnalyzerTag /> : <span className="font-mono">{inv.model}</span>}
      </div>
      <div>
        <p className="text-lg font-medium">{a.summary}</p>
        {a.impact && <p className="mt-1 text-sm text-fg-muted">{a.impact}</p>}
      </div>
      <section aria-labelledby="causes">
        <h3 id="causes" className="mb-2 text-sm font-semibold">Probable causes</h3>
        <ol className="space-y-4">
          {a.probable_causes.map((c, i) => (
            <CauseView key={c.cause} cause={c} rank={i + 1} inv={inv} />
          ))}
        </ol>
      </section>
      {a.recommended_actions.length > 0 && (
        <section aria-labelledby="actions">
          <h3 id="actions" className="mb-2 text-sm font-semibold">Recommended next steps</h3>
          <ul className="space-y-3">
            {a.recommended_actions.map((act) => {
              const p = act.proposal_id ? proposals.get(act.proposal_id) : undefined;
              const risk = RISK[act.risk];
              const mayDecide = canAct && p?.status === "proposed" && (act.risk !== "destructive" || isAdmin);
              return (
                <li key={act.action} className="text-sm">
                  <div>{act.action}</div>
                  <div className="flex flex-wrap items-center gap-2 text-xs">
                    <span className={risk.className}>{risk.label}</span>
                    {p && p.status !== "proposed" && (
                      <span className="text-fg-subtle">
                        · {p.status === "approved" ? "Approved (not executed by DevPulse)" : "Rejected"}
                      </span>
                    )}
                    {p?.status === "proposed" && act.risk === "destructive" && !isAdmin && (
                      <span className="text-fg-subtle">· An admin must decide</span>
                    )}
                  </div>
                  {mayDecide && (
                    <div className="mt-1 flex gap-2">
                      <Button
                        size="sm"
                        variant="secondary"
                        loading={deciding === p.id}
                        onClick={() => {
                          if (
                            window.confirm(
                              `Approve “${p.description}”?\n\nThis records your decision on the incident. ` +
                                "DevPulse does not run it: your team carries it out.",
                            )
                          )
                            onDecide(p.id, true);
                        }}
                      >
                        Approve
                      </Button>
                      <Button size="sm" variant="ghost" disabled={deciding === p.id} onClick={() => onDecide(p.id, false)}>
                        Reject
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
          <h3 id="gaps" className="mb-1 text-sm font-semibold">What DevPulse could not see</h3>
          <ul className="list-disc space-y-0.5 pl-5 text-xs text-fg-muted">
            {a.data_gaps.map((g) => (
              <li key={g}>{g}</li>
            ))}
          </ul>
        </section>
      )}
      {(a.adjustments ?? []).map((adj) => (
        <p key={adj} className="text-xs text-fg-subtle">Adjusted: {adj}</p>
      ))}
      {a.limitations && <p className="text-xs italic text-fg-subtle">{a.limitations}</p>}
    </div>
  );
}

function Chat({ orgId, inv, canAct }: { orgId: string; inv: Investigation; canAct: boolean }) {
  const qc = useQueryClient();
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
      <h3 id="ask" className="text-sm font-semibold">Ask a follow-up</h3>
      {visible.length === 0 && !ask.isPending && (
        <p className="text-xs text-fg-subtle">
          e.g. “When did errors start?” Answers cite evidence. Copilot can only read data, never change anything.
        </p>
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
                Looked up {m.tool_name?.replaceAll("_", " ")} → {m.evidence_refs.join(", ")}
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
        {ask.isPending && <li className="text-xs text-fg-subtle" aria-live="polite">Looking into it…</li>}
      </ul>
      {ask.isError && <Alert>{aiErrorMessage(ask.error instanceof ApiError ? ask.error.problem.code : null, ask.error.message)}</Alert>}
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
          <label htmlFor="ai-question" className="sr-only">Follow-up question</label>
          <input
            id="ai-question"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            maxLength={2000}
            placeholder="Ask a follow-up question"
            className="min-h-10 flex-1 rounded-md border border-line bg-canvas px-3 text-sm"
          />
          <Button type="submit" loading={ask.isPending}>Ask</Button>
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
    mutationFn: () => api.post<Investigation>(`orgs/${orgId}/incidents/${incidentRef}/investigations`),
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
    start.error instanceof ApiError ? aiErrorMessage(start.error.problem.code, start.error.message) : null;

  return (
    <section aria-labelledby="ai-analysis" className="rounded-lg border border-line bg-surface p-6">
      <div className="mb-4 flex items-center justify-between gap-2">
        <h2 id="ai-analysis" className="font-semibold">AI analysis</h2>
        {inv && !ACTIVE.has(inv.status) && canAct && (
          <Button size="sm" variant="ghost" loading={start.isPending} onClick={() => start.mutate()}>
            Run again
          </Button>
        )}
      </div>
      {startError && <Alert className="mb-4">{startError}</Alert>}
      {latest.isPending ? (
        <div className="h-24 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label="Loading AI analysis" />
      ) : latest.isError ? (
        <Alert>
          Couldn&apos;t load the AI analysis.{" "}
          <Button variant="ghost" size="sm" onClick={() => latest.refetch()}>Retry</Button>
        </Alert>
      ) : !inv ? (
        <div className="space-y-3">
          <p className="text-sm text-fg-muted">
            Copilot reads this incident&apos;s metrics, logs, deployments and similar past incidents, then suggests
            probable causes, each with the evidence behind it.
          </p>
          {canAct && (
            <Button loading={start.isPending} onClick={() => start.mutate()}>
              Investigate with AI
            </Button>
          )}
        </div>
      ) : ACTIVE.has(inv.status) ? (
        <p className="flex items-center gap-2 text-sm" aria-live="polite">
          <span aria-hidden className="size-3.5 animate-spin rounded-full border-2 border-current border-r-transparent" />
          {PROGRESS[inv.status]}
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
          {decide.error && <Alert>{decide.error.message}</Alert>}
          <div className="flex items-center gap-2 text-xs text-fg-subtle">
            Was this helpful?
            <Button
              size="sm"
              variant={inv.my_feedback === true ? "secondary" : "ghost"}
              aria-pressed={inv.my_feedback === true}
              onClick={() => feedback.mutate({ invId: inv.id, helpful: true })}
            >
              Yes
            </Button>
            <Button
              size="sm"
              variant={inv.my_feedback === false ? "secondary" : "ghost"}
              aria-pressed={inv.my_feedback === false}
              onClick={() => feedback.mutate({ invId: inv.id, helpful: false })}
            >
              No
            </Button>
          </div>
          <Chat orgId={orgId} inv={inv} canAct={canAct} />
        </div>
      ) : (
        <div className="space-y-2">
          <p className="font-medium">Analysis unavailable</p>
          <p className="text-sm text-fg-muted">{aiErrorMessage(inv.error_code, inv.error_detail)}</p>
          <p className="text-xs text-fg-subtle">Incident actions are not affected.</p>
        </div>
      )}
    </section>
  );
}

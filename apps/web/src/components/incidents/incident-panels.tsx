"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState, type FormEvent } from "react";

import { fmt, type Marker, TimeSeriesChart, toPoints } from "@/components/charts/time-series";
import { metricsQuery } from "@/components/services/service-detail";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { timeAgo } from "@/components/ui/status";
import { api, ApiError, request } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Incident = components["schemas"]["IncidentOut"];
type Metrics = components["schemas"]["MetricsOut"];
type Correlated = components["schemas"]["CorrelatedDeploymentOut"];
type Comment = components["schemas"]["CommentOut"];

const HOUR = 3_600_000;

/** Window shown around an incident: 1 h before the start → resolution (or now), ≤ 3 h. */
export function incidentWindow(i: Pick<Incident, "started_at" | "resolved_at">, now = Date.now()): { from: Date; to: Date } {
  const start = new Date(i.started_at).getTime();
  const end = Math.min(i.resolved_at ? new Date(i.resolved_at).getTime() + 15 * 60_000 : now, start + 2 * HOUR, now);
  return { from: new Date(start - HOUR), to: new Date(Math.max(end, start + 5 * 60_000)) };
}

export function CorrelationPanel({ orgId, incident }: { orgId: string; incident: Incident }) {
  // "Now" is fixed per mount (and re-taken when the incident changes): deriving it on every
  // render would change the query key each time and refetch in a loop.
  const [now] = useState(Date.now);
  const { from, to } = useMemo(
    () => incidentWindow({ started_at: incident.started_at, resolved_at: incident.resolved_at }, now),
    [incident.started_at, incident.resolved_at, now],
  );
  const svc = incident.service;
  const metrics = useQuery({
    queryKey: ["orgs", orgId, "incident", incident.key, "metrics", from.getTime(), to.getTime()],
    queryFn: () =>
      api.get<Metrics>(
        `orgs/${orgId}/services/${svc!.id}/metrics?${metricsQuery(["http.server.duration_ms:p95", "http.server.error_rate"], from, to)}`,
      ),
    enabled: !!svc,
  });
  const deploys = useQuery({
    queryKey: ["orgs", orgId, "incident", incident.key, "deployments"],
    queryFn: () => api.get<Correlated[]>(`orgs/${orgId}/incidents/${incident.key}/deployments`),
  });
  if (!svc) {
    return <p className="text-sm text-fg-subtle">This incident isn&apos;t linked to a service, so there is no telemetry to correlate.</p>;
  }
  const markers: Marker[] = [
    ...(deploys.data ?? []).map((d) => ({ t: new Date(d.started_at).getTime(), label: d.version, tone: "deploy" as const })),
    { t: new Date(incident.started_at).getTime(), label: "start", tone: "incident" },
    ...(incident.acknowledged_at ? [{ t: new Date(incident.acknowledged_at).getTime(), label: "ack", tone: "event" as const }] : []),
    ...(incident.resolved_at ? [{ t: new Date(incident.resolved_at).getTime(), label: "resolved", tone: "event" as const }] : []),
  ];
  const s = metrics.data?.series ?? [];
  return (
    <section aria-labelledby="correlation" className="space-y-3 rounded-lg border border-line bg-surface p-6">
      <h2 id="correlation" className="font-semibold">
        Correlation
      </h2>
      <p className="text-xs text-fg-subtle">
        {svc.name}, 1 hour before the incident until {incident.resolved_at ? "shortly after resolution" : "now"}.{" "}
        <span className="text-violet">┆ deploys</span> are suspected from timing only.
      </p>
      {metrics.isError ? (
        <Alert>Couldn&apos;t load metrics.</Alert>
      ) : (
        <div className="grid gap-4 xl:grid-cols-2" aria-busy={metrics.isPending}>
          <TimeSeriesChart
            title="Latency p95"
            points={toPoints(s.find((x) => x.name === "http.server.duration_ms")?.points)}
            format={fmt.ms}
            markers={markers}
            height={180}
            domain={[from.getTime(), to.getTime()]}
            loading={metrics.isPending}
          />
          <TimeSeriesChart
            title="Error rate"
            points={toPoints(s.find((x) => x.name === "http.server.error_rate")?.points)}
            format={fmt.pct}
            markers={markers}
            height={180}
            domain={[from.getTime(), to.getTime()]}
            loading={metrics.isPending}
          />
        </div>
      )}
      {(deploys.data ?? []).length > 0 && (
        <ul className="space-y-1 text-xs">
          {deploys.data!.map((d) => (
            <li key={d.deployment_id}>
              <span className="font-mono">{d.version}</span> · {timeAgo(d.started_at)} · {d.status} · {d.correlation} (
              {Math.round(d.score * 100)}%){d.commit_message ? ` · ${d.commit_message.split("\n")[0]}` : ""}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function newId(): string {
  return crypto.randomUUID();
}

/** Incident commands with optimistic concurrency (If-Match) and safe retries (Idempotency-Key). */
export function ActionsBar({ orgId, incident, myUserId }: { orgId: string; incident: Incident; myUserId: string }) {
  const qc = useQueryClient();
  const run = useMutation({
    mutationFn: (v: { path: string; body?: unknown }) =>
      request<Incident>(`/api/v1/orgs/${orgId}/incidents/${incident.key}/${v.path}`, {
        method: "POST",
        json: v.body ?? {},
        headers: { "If-Match": `"${incident.version}"`, "Idempotency-Key": newId() },
      }),
    onSuccess: (updated) => {
      qc.setQueryData(["orgs", orgId, "incident", incident.key], updated);
    },
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: ["orgs", orgId, "incident", incident.key] });
    },
  });
  const open = incident.status !== "resolved";
  const conflict = run.error instanceof ApiError && run.error.status === 409;

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {incident.status === "triggered" && (
          <Button loading={run.isPending && run.variables?.path === "acknowledge"} onClick={() => run.mutate({ path: "acknowledge" })}>
            Acknowledge
          </Button>
        )}
        {open && (
          <Button
            variant="secondary"
            loading={run.isPending && run.variables?.path === "resolve"}
            onClick={() => {
              const note = window.prompt("Resolution note (optional)");
              if (note === null) return;
              run.mutate({ path: "resolve", body: { resolution_note: note.trim() || null } });
            }}
          >
            Resolve
          </Button>
        )}
        {open && incident.assignee?.id !== myUserId && (
          <Button variant="ghost" disabled={run.isPending} onClick={() => run.mutate({ path: "assign", body: { user_id: myUserId } })}>
            Assign to me
          </Button>
        )}
        {open && (
          <Button variant="ghost" disabled={run.isPending} onClick={() => run.mutate({ path: "escalate" })}>
            Escalate
          </Button>
        )}
        {!open && (
          <Button variant="secondary" disabled={run.isPending} onClick={() => run.mutate({ path: "reopen" })}>
            Reopen
          </Button>
        )}
      </div>
      {run.isError && (
        <Alert>
          {conflict
            ? "This incident changed while you were looking at it. It has been refreshed; check its status and try again."
            : run.error.message}
        </Alert>
      )}
    </div>
  );
}

export function Comments({ orgId, incidentRef, canAct }: { orgId: string; incidentRef: string; canAct: boolean }) {
  const qc = useQueryClient();
  const key = ["orgs", orgId, "incident", incidentRef, "comments"];
  const [clientId, setClientId] = useState(newId);
  const list = useQuery({
    queryKey: key,
    queryFn: () => api.get<{ items: Comment[] }>(`orgs/${orgId}/incidents/${incidentRef}/comments?limit=200`),
    refetchInterval: 15_000,
  });
  const add = useMutation({
    mutationFn: (body: string) => api.post<Comment>(`orgs/${orgId}/incidents/${incidentRef}/comments`, { body, client_id: clientId }),
    onSuccess: () => {
      setClientId(newId()); // keep the id across retries of the same comment only
      void qc.invalidateQueries({ queryKey: key });
    },
  });
  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const body = String(new FormData(form).get("body") ?? "").trim();
    if (!body) return;
    add.mutate(body, { onSuccess: () => form.reset() });
  }
  return (
    <section aria-labelledby="comments" className="space-y-2">
      <h2 id="comments" className="text-sm font-semibold">
        Comments
      </h2>
      <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
        {(list.data?.items ?? []).length === 0 && <li className="px-3 py-2 text-fg-subtle">No comments yet.</li>}
        {(list.data?.items ?? []).map((c) => (
          <li key={c.id} className="px-3 py-2">
            <p className="whitespace-pre-wrap">{c.body}</p>
            <p className="text-xs text-fg-subtle">
              {c.author?.display_name ?? "Unknown"} · {timeAgo(c.created_at)}
            </p>
          </li>
        ))}
      </ul>
      {canAct && (
        <form onSubmit={onSubmit} className="space-y-2">
          <label htmlFor="comment" className="sr-only">
            Add a comment
          </label>
          <textarea
            id="comment"
            name="body"
            rows={2}
            maxLength={10000}
            placeholder="Add a comment"
            className="w-full rounded-md border border-line bg-canvas px-3 py-2 text-sm"
          />
          <Button type="submit" size="sm" loading={add.isPending}>
            Comment
          </Button>
          {add.isError && <Alert>{add.error.message}</Alert>}
        </form>
      )}
    </section>
  );
}

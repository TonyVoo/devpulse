"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Alert, Card, EmptyState } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { timeAgo } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Integration = components["schemas"]["IntegrationOut"];
type Created = components["schemas"]["IntegrationCreatedOut"];
type Service = components["schemas"]["ServiceOut"];

function Copyable({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="space-y-1">
      <p className="text-xs font-medium text-fg-muted">{label}</p>
      <div className="flex items-center gap-2">
        <code className="min-w-0 flex-1 break-all rounded bg-canvas px-2 py-1 text-xs">{value}</code>
        <Button size="sm" variant="secondary" onClick={() => void navigator.clipboard.writeText(value).then(() => setCopied(true))}>
          {copied ? "Copied" : "Copy"}
        </Button>
      </div>
    </div>
  );
}

function Setup({ created, apiOrigin }: { created: Created; apiOrigin: string }) {
  return (
    <Alert tone="info" className="space-y-3">
      <p className="font-medium">Finish the setup in GitHub (Settings → Webhooks → Add webhook):</p>
      <Copyable label="Payload URL" value={`${apiOrigin}${created.webhook_path}`} />
      <Copyable label="Secret (shown once; DevPulse stores it encrypted)" value={created.webhook_secret} />
      <ol className="list-decimal space-y-1 pl-5 text-xs">
        <li>Content type: <code>application/json</code>.</li>
        <li>Events: choose “Let me select individual events”, then <strong>Deployments</strong> and <strong>Deployment statuses</strong>.</li>
        <li>GitHub sends a ping; it should show a green check.</li>
      </ol>
    </Alert>
  );
}

export function IntegrationsView({ orgId, canManage, apiOrigin }: { orgId: string; canManage: boolean; apiOrigin: string }) {
  const qc = useQueryClient();
  const [created, setCreated] = useState<Created | null>(null);
  const [repos, setRepos] = useState<{ repo: string; service: string }[]>([]);
  const list = useQuery({
    queryKey: ["orgs", orgId, "integrations"],
    queryFn: () => api.get<Integration[]>(`orgs/${orgId}/integrations`),
  });
  const services = useQuery({
    queryKey: ["orgs", orgId, "services"],
    queryFn: () => api.get<{ items: Service[] }>(`orgs/${orgId}/services?limit=200`),
    enabled: canManage,
  });
  const create = useMutation({
    mutationFn: (body: components["schemas"]["IntegrationIn"]) => api.post<Created>(`orgs/${orgId}/integrations`, body),
    onSuccess: (c) => {
      setCreated(c);
      setRepos([]);
      void qc.invalidateQueries({ queryKey: ["orgs", orgId, "integrations"] });
    },
  });
  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`orgs/${orgId}/integrations/${id}`),
    onSettled: () => qc.invalidateQueries({ queryKey: ["orgs", orgId, "integrations"] }),
  });

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const name = String(new FormData(e.currentTarget).get("name"));
    const repo_map = Object.fromEntries(repos.filter((r) => r.repo.trim() && r.service).map((r) => [r.repo.trim(), r.service]));
    create.mutate({ kind: "github", name, repo_map });
  }

  return (
    <div className="space-y-6">
      {canManage && (
        <Card className="space-y-4">
          <h2 className="font-semibold">Connect GitHub deployments</h2>
          <p className="text-sm text-fg-muted">
            DevPulse records GitHub deployment events and links them to services, so incidents can show which release
            preceded them. Repositories are matched to services by their repository URL; add explicit mappings below
            if the URLs differ.
          </p>
          <form method="post" onSubmit={onSubmit} className="space-y-3">
            <Field label="Name" name="name" required defaultValue="GitHub" />
            {repos.map((r, i) => (
              <div key={i} className="flex flex-wrap items-end gap-2">
                <div className="min-w-48 flex-1">
                  <Field
                    label="Repository (owner/name)"
                    value={r.repo}
                    placeholder="acme/checkout"
                    onChange={(e) => setRepos(repos.map((x, j) => (j === i ? { ...x, repo: e.target.value } : x)))}
                  />
                </div>
                <label className="flex flex-col gap-1.5 text-xs font-medium text-fg-muted">
                  Service
                  <Select
                    value={r.service}
                    onChange={(e) => setRepos(repos.map((x, j) => (j === i ? { ...x, service: e.target.value } : x)))}
                    
                  >
                    <option value="">Choose…</option>
                    {(services.data?.items ?? []).map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.name}
                      </option>
                    ))}
                  </Select>
                </label>
                <Button type="button" variant="ghost" size="sm" onClick={() => setRepos(repos.filter((_, j) => j !== i))}>
                  Remove
                </Button>
              </div>
            ))}
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="secondary" onClick={() => setRepos([...repos, { repo: "", service: "" }])}>
                Add repository mapping
              </Button>
              <Button type="submit" loading={create.isPending}>
                Create webhook
              </Button>
            </div>
          </form>
          {create.isError && <Alert>{create.error instanceof ApiError ? create.error.problem.detail : create.error.message}</Alert>}
          {created && <Setup created={created} apiOrigin={apiOrigin} />}
        </Card>
      )}
      {list.isPending ? (
        <div className="h-24 animate-pulse rounded-md bg-raised" role="status" aria-busy aria-label="Loading integrations" />
      ) : list.isError ? (
        <Alert>Couldn&apos;t load integrations.</Alert>
      ) : list.data.length === 0 ? (
        <EmptyState title="No integrations yet" description="Connect GitHub to record deployments automatically." />
      ) : (
        <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
          {list.data.map((i) => {
            const mapped = Object.keys((i.config.repo_map as Record<string, string> | undefined) ?? {});
            return (
              <li key={i.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <div className="font-medium">
                    {i.name} <span className="text-xs text-fg-subtle">GitHub</span>
                  </div>
                  <div className="break-all text-xs text-fg-subtle">
                    {apiOrigin}
                    {i.webhook_path} · added {timeAgo(i.created_at)}
                    {mapped.length > 0 && ` · ${mapped.join(", ")}`}
                  </div>
                </div>
                {canManage && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (window.confirm(`Delete “${i.name}”? GitHub deliveries to its URL will be rejected.`)) remove.mutate(i.id);
                    }}
                  >
                    Delete
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

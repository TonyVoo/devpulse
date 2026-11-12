"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Alert, Card } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { timeAgo } from "@/components/ui/status";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Member = components["schemas"]["MemberOut"];
type Invitation = components["schemas"]["InvitationOut"];
type Created = components["schemas"]["InvitationCreatedOut"];
type Role = Member["role"];

const ROLE_LABEL: Record<Role, string> = {
  owner: "Owner",
  admin: "Admin",
  engineer: "Engineer",
  viewer: "Viewer",
};
const RANK: Record<Role, number> = { viewer: 0, engineer: 1, admin: 2, owner: 3 };

/** Roles the current user may grant (mirrors the API: never above your own). */
export function grantableRoles(myRole: Role): Role[] {
  return (Object.keys(RANK) as Role[]).filter((r) => RANK[r] <= RANK[myRole]).reverse();
}

function errorText(e: unknown): string {
  return e instanceof ApiError ? e.problem.detail : "Something went wrong.";
}

function InviteForm({ orgId, myRole }: { orgId: string; myRole: Role }) {
  const qc = useQueryClient();
  const [link, setLink] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const invite = useMutation({
    mutationFn: (body: { email: string; role: Role }) => api.post<Created>(`orgs/${orgId}/invitations`, body),
    onSuccess: (inv) => {
      setLink(`${window.location.origin}/invite/${inv.token}`);
      setCopied(false);
      void qc.invalidateQueries({ queryKey: ["orgs", orgId, "invitations"] });
    },
  });

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    invite.mutate({ email: String(data.get("email")), role: data.get("role") as Role });
    e.currentTarget.reset();
  }

  return (
    <Card className="space-y-4">
      <h2 className="font-semibold">Invite someone</h2>
      <form method="post" onSubmit={onSubmit} className="flex flex-wrap items-end gap-3">
        <div className="min-w-56 flex-1">
          <Field label="Email" name="email" type="email" required autoComplete="off" />
        </div>
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          Role
          <select name="role" defaultValue="engineer" className="min-h-10 rounded-md border border-line bg-canvas px-2 text-sm text-fg">
            {grantableRoles(myRole).map((r) => (
              <option key={r} value={r}>
                {ROLE_LABEL[r]}
              </option>
            ))}
          </select>
        </label>
        <Button type="submit" loading={invite.isPending}>
          Create invite link
        </Button>
      </form>
      {invite.isError && <Alert>{errorText(invite.error)}</Alert>}
      {link && (
        <Alert tone="info">
          <p className="mb-2">
            Send this link to them. It is shown once, works only for that email address and expires in 7 days.
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <code className="min-w-0 flex-1 break-all rounded bg-canvas px-2 py-1 text-xs">{link}</code>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                void navigator.clipboard.writeText(link).then(() => setCopied(true));
              }}
            >
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
        </Alert>
      )}
    </Card>
  );
}

function Invitations({ orgId }: { orgId: string }) {
  const qc = useQueryClient();
  const list = useQuery({
    queryKey: ["orgs", orgId, "invitations"],
    queryFn: () => api.get<Invitation[]>(`orgs/${orgId}/invitations`),
  });
  const revoke = useMutation({
    mutationFn: (id: string) => api.delete(`orgs/${orgId}/invitations/${id}`),
    onSettled: () => qc.invalidateQueries({ queryKey: ["orgs", orgId, "invitations"] }),
  });
  if (!list.data?.length) return null;
  return (
    <section aria-labelledby="pending" className="space-y-2">
      <h2 id="pending" className="text-sm font-semibold">
        Pending invitations
      </h2>
      <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
        {list.data.map((i) => (
          <li key={i.id} className="flex flex-wrap items-center gap-3 px-4 py-2">
            <span className="min-w-0 flex-1 truncate">{i.email}</span>
            <span className="text-fg-muted">{ROLE_LABEL[i.role]}</span>
            <span className="text-xs text-fg-subtle">sent {timeAgo(i.created_at)}</span>
            <Button size="sm" variant="ghost" loading={revoke.isPending && revoke.variables === i.id} onClick={() => revoke.mutate(i.id)}>
              Revoke
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function MembersTable({
  orgId,
  myUserId,
  myRole,
}: {
  orgId: string;
  myUserId: string;
  myRole: Role;
}) {
  const qc = useQueryClient();
  const canManage = myRole === "owner" || myRole === "admin";
  const key = ["orgs", orgId, "members"];
  const members = useQuery({ queryKey: key, queryFn: () => api.get<Member[]>(`orgs/${orgId}/members`) });
  const change = useMutation({
    mutationFn: (v: { userId: string; role: Role }) => api.patch(`orgs/${orgId}/members/${v.userId}`, { role: v.role }),
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });
  const remove = useMutation({
    mutationFn: (userId: string) => api.delete(`orgs/${orgId}/members/${userId}`),
    onSettled: () => qc.invalidateQueries({ queryKey: key }),
  });

  if (members.isPending) {
    return (
      <div role="status" aria-busy className="space-y-2" aria-label="Loading members">
        {[0, 1, 2].map((i) => (
          <div key={i} className="h-14 animate-pulse rounded-md bg-surface" />
        ))}
      </div>
    );
  }
  if (members.isError) {
    return (
      <Alert>
        Couldn&apos;t load members: {members.error.message}{" "}
        <Button variant="ghost" size="sm" onClick={() => members.refetch()}>
          Retry
        </Button>
      </Alert>
    );
  }
  const error = change.error ?? remove.error;
  return (
    <div className="space-y-6">
      {canManage && <InviteForm orgId={orgId} myRole={myRole} />}
      {error && <Alert>{errorText(error)}</Alert>}
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full min-w-[560px] text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-fg-subtle">
            <tr className="border-b border-line">
              <th scope="col" className="px-4 py-3 font-medium">Name</th>
              <th scope="col" className="px-4 py-3 font-medium">Email</th>
              <th scope="col" className="px-4 py-3 font-medium">Role</th>
              <th scope="col" className="px-4 py-3 font-medium">Joined</th>
              {canManage && (
                <th scope="col" className="px-4 py-3 font-medium">
                  <span className="sr-only">Actions</span>
                </th>
              )}
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {members.data.map((m) => {
              const editable = canManage && m.user_id !== myUserId && RANK[m.role] <= RANK[myRole];
              return (
                <tr key={m.user_id}>
                  <td className="px-4 py-3">
                    {m.display_name}
                    {m.user_id === myUserId && <span className="ml-1 text-xs text-fg-subtle">(you)</span>}
                  </td>
                  <td className="px-4 py-3 text-fg-muted">{m.email}</td>
                  <td className="px-4 py-3">
                    {editable ? (
                      <select
                        aria-label={`Role for ${m.display_name}`}
                        value={m.role}
                        disabled={change.isPending}
                        onChange={(e) => change.mutate({ userId: m.user_id, role: e.target.value as Role })}
                        className="min-h-9 rounded-md border border-line bg-canvas px-2 text-sm"
                      >
                        {grantableRoles(myRole).map((r) => (
                          <option key={r} value={r}>
                            {ROLE_LABEL[r]}
                          </option>
                        ))}
                      </select>
                    ) : (
                      ROLE_LABEL[m.role]
                    )}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs text-fg-muted">
                    {new Date(m.joined_at).toLocaleDateString()}
                  </td>
                  {canManage && (
                    <td className="px-4 py-3 text-right">
                      {editable && (
                        <Button
                          size="sm"
                          variant="ghost"
                          loading={remove.isPending && remove.variables === m.user_id}
                          onClick={() => {
                            if (window.confirm(`Remove ${m.display_name} from this organization? They lose access immediately.`))
                              remove.mutate(m.user_id);
                          }}
                        >
                          Remove
                        </Button>
                      )}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {canManage && <Invitations orgId={orgId} />}
    </div>
  );
}

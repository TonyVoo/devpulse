"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Alert, Card } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";

type Member = components["schemas"]["MemberOut"];
type Invitation = components["schemas"]["InvitationOut"];
type Created = components["schemas"]["InvitationCreatedOut"];
type Role = Member["role"];

const RANK: Record<Role, number> = { viewer: 0, engineer: 1, admin: 2, owner: 3 };

/** Roles the current user may grant (mirrors the API: never above your own). */
export function grantableRoles(myRole: Role): Role[] {
  return (Object.keys(RANK) as Role[]).filter((r) => RANK[r] <= RANK[myRole]).reverse();
}


function InviteForm({ orgId, myRole }: { orgId: string; myRole: Role }) {
  const qc = useQueryClient();
  const { t } = useI18n();
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
      <h2 className="font-semibold">{t("members.invite")}</h2>
      <form method="post" onSubmit={onSubmit} className="flex flex-wrap items-end gap-3">
        <div className="min-w-56 flex-1">
          <Field label={t("common.email")} name="email" type="email" required autoComplete="off" />
        </div>
        <label className="flex flex-col gap-1.5 text-xs font-medium tracking-wide text-fg-muted">
          {t("members.role")}
          <Select name="role" defaultValue="engineer">
            {grantableRoles(myRole).map((r) => (
              <option key={r} value={r}>
                {t(`roles.${r}`)}
              </option>
            ))}
          </Select>
        </label>
        <Button type="submit" loading={invite.isPending}>
          {t("members.createLink")}
        </Button>
      </form>
      {invite.isError && <Alert>{errorText(invite.error, t)}</Alert>}
      {link && (
        <Alert tone="info">
          <p className="mb-2">{t("members.linkHint")}</p>
          <div className="flex flex-wrap items-center gap-2">
            <code className="min-w-0 flex-1 break-all rounded bg-canvas px-2 py-1 text-xs">{link}</code>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                void navigator.clipboard.writeText(link).then(() => setCopied(true));
              }}
            >
              {copied ? t("common.copied") : t("common.copy")}
            </Button>
          </div>
        </Alert>
      )}
    </Card>
  );
}

function Invitations({ orgId }: { orgId: string }) {
  const qc = useQueryClient();
  const { t, ago } = useI18n();
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
        {t("members.pending")}
      </h2>
      <ul className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
        {list.data.map((i) => (
          <li key={i.id} className="flex flex-wrap items-center gap-3 px-4 py-2">
            <span className="min-w-0 flex-1 truncate">{i.email}</span>
            <span className="text-fg-muted">{t(`roles.${i.role}`)}</span>
            <span className="text-xs text-fg-subtle">{t("members.sent", { ago: ago(i.created_at) })}</span>
            <Button size="sm" variant="ghost" loading={revoke.isPending && revoke.variables === i.id} onClick={() => revoke.mutate(i.id)}>
              {t("common.revoke")}
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
  const { t, date } = useI18n();
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
      <div role="status" aria-busy className="space-y-2" aria-label={t("members.loading")}>
        {[0, 1, 2].map((i) => (
          <div key={i} className="h-14 animate-pulse rounded-md bg-raised" />
        ))}
      </div>
    );
  }
  if (members.isError) {
    return (
      <Alert>
        {t("members.loadError", { error: errorText(members.error, t) })}{" "}
        <Button variant="ghost" size="sm" onClick={() => members.refetch()}>
          {t("common.retry")}
        </Button>
      </Alert>
    );
  }
  const error = change.error ?? remove.error;
  return (
    <div className="space-y-6">
      {canManage && <InviteForm orgId={orgId} myRole={myRole} />}
      {error && <Alert>{errorText(error, t)}</Alert>}
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-fg-subtle">
            <tr className="border-b border-line">
              <th scope="col" className="px-4 py-3 font-medium">{t("members.colName")}</th>
              <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">{t("members.colEmail")}</th>
              <th scope="col" className="px-4 py-3 font-medium">{t("members.colRole")}</th>
              <th scope="col" className="hidden px-4 py-3 font-medium md:table-cell">{t("members.colJoined")}</th>
              {canManage && (
                <th scope="col" className="px-4 py-3 font-medium">
                  <span className="sr-only">{t("members.actions")}</span>
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
                    {m.user_id === myUserId && <span className="ml-1 text-xs text-fg-subtle">{t("members.you")}</span>}
                    <div className="break-all text-xs text-fg-muted sm:hidden">{m.email}</div>
                  </td>
                  <td className="hidden break-all px-4 py-3 text-fg-muted sm:table-cell">{m.email}</td>
                  <td className="px-4 py-3">
                    {editable ? (
                      <Select
                        className="w-32"
                        aria-label={t("members.roleFor", { name: m.display_name })}
                        value={m.role}
                        disabled={change.isPending}
                        onChange={(e) => change.mutate({ userId: m.user_id, role: e.target.value as Role })}
                        size="sm"
                      >
                        {grantableRoles(myRole).map((r) => (
                          <option key={r} value={r}>
                            {t(`roles.${r}`)}
                          </option>
                        ))}
                      </Select>
                    ) : (
                      t(`roles.${m.role}`)
                    )}
                  </td>
                  <td className="hidden px-4 py-3 font-mono text-xs text-fg-muted md:table-cell">
                    {date(m.joined_at, { dateStyle: "medium" })}
                  </td>
                  {canManage && (
                    <td className="px-4 py-3 text-right">
                      {editable && (
                        <Button
                          size="sm"
                          variant="ghost"
                          loading={remove.isPending && remove.variables === m.user_id}
                          onClick={() => {
                            if (window.confirm(t("members.confirmRemove", { name: m.display_name })))
                              remove.mutate(m.user_id);
                          }}
                        >
                          {t("common.remove")}
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

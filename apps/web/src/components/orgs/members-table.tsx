"use client";

import { useQuery } from "@tanstack/react-query";

import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/card";
import { api } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Member = components["schemas"]["MemberOut"];

const ROLE_LABEL: Record<Member["role"], string> = {
  owner: "Owner",
  admin: "Admin",
  engineer: "Engineer",
  viewer: "Viewer",
};

export function MembersTable({ orgId }: { orgId: string }) {
  const members = useQuery({
    queryKey: ["orgs", orgId, "members"],
    queryFn: () => api.get<Member[]>(`orgs/${orgId}/members`),
  });

  if (members.isPending) {
    return (
      <div aria-busy className="space-y-2" aria-label="Loading members">
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
  return (
    <div className="overflow-x-auto rounded-lg border border-line bg-surface">
      <table className="w-full min-w-[560px] text-sm">
        <thead className="text-left text-xs uppercase tracking-wide text-fg-subtle">
          <tr className="border-b border-line">
            <th scope="col" className="px-4 py-3 font-medium">Name</th>
            <th scope="col" className="px-4 py-3 font-medium">Email</th>
            <th scope="col" className="px-4 py-3 font-medium">Role</th>
            <th scope="col" className="px-4 py-3 font-medium">Joined</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {members.data.map((m) => (
            <tr key={m.user_id}>
              <td className="px-4 py-3">{m.display_name}</td>
              <td className="px-4 py-3 text-fg-muted">{m.email}</td>
              <td className="px-4 py-3">{ROLE_LABEL[m.role]}</td>
              <td className="px-4 py-3 font-mono text-xs text-fg-muted">
                {new Date(m.joined_at).toLocaleDateString()}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

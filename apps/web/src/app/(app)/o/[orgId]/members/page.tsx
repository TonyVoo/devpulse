import type { Metadata } from "next";

import { MembersTable } from "@/components/orgs/members-table";

export const metadata: Metadata = { title: "Members" };

export default async function MembersPage({ params }: PageProps<"/o/[orgId]/members">) {
  const { orgId } = await params;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Members</h1>
        <p className="mt-1 text-sm text-fg-muted">
          People with access to this organization and their roles.
        </p>
      </header>
      <MembersTable orgId={orgId} />
    </div>
  );
}

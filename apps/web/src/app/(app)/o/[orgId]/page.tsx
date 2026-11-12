import type { Metadata } from "next";

import { OverviewView } from "@/components/overview/overview-view";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Overview" };

export default async function OrgOverview({ params }: PageProps<"/o/[orgId]">) {
  const { orgId } = await params;
  const me = await getMe();
  const org = me.memberships.find((m) => m.id === orgId);
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <p className="font-mono text-xs uppercase tracking-widest text-fg-subtle">{org?.slug}</p>
        <h1 className="text-2xl font-semibold">{org?.name}</h1>
      </header>
      <OverviewView orgId={orgId} />
    </div>
  );
}

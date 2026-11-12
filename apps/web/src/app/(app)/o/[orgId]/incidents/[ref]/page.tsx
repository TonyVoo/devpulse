import type { Metadata } from "next";

import { IncidentDetail } from "@/components/incidents/incident-detail";
import { getMe } from "@/lib/server-api";

export async function generateMetadata({ params }: PageProps<"/o/[orgId]/incidents/[ref]">): Promise<Metadata> {
  const { ref } = await params;
  return { title: decodeURIComponent(ref).toUpperCase() };
}

export default async function IncidentPage({ params }: PageProps<"/o/[orgId]/incidents/[ref]">) {
  const { orgId, ref } = await params;
  const me = await getMe();
  const role = me.memberships.find((m) => m.id === orgId)?.role ?? "viewer";
  return (
    <div className="px-4 py-6 md:px-8 md:py-8">
      <IncidentDetail
        orgId={orgId}
        incidentRef={decodeURIComponent(ref)}
        canAct={role !== "viewer"}
        isAdmin={role === "owner" || role === "admin"}
        myUserId={me.id}
      />
    </div>
  );
}

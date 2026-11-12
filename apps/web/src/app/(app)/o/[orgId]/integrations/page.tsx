import type { Metadata } from "next";

import { IntegrationsView } from "@/components/integrations/integrations-view";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Integrations" };

export default async function IntegrationsPage({ params }: PageProps<"/o/[orgId]/integrations">) {
  const { orgId } = await params;
  const me = await getMe();
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Integrations</h1>
      </header>
      <IntegrationsView
        orgId={orgId}
        canManage={role === "owner" || role === "admin"}
        apiOrigin={process.env.API_PUBLIC_URL ?? "http://localhost:8000"}
      />
    </div>
  );
}

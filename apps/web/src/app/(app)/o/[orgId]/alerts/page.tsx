import type { Metadata } from "next";

import { AlertRulesView } from "@/components/alerts/alert-rules";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Alert rules" };

export default async function AlertsPage({ params }: PageProps<"/o/[orgId]/alerts">) {
  const { orgId } = await params;
  const me = await getMe();
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Alert rules</h1>
        <p className="mt-1 text-sm text-fg-muted">
          A rule watches one metric of one service. When it stays past the threshold for the hold time, DevPulse opens
          an incident.
        </p>
      </header>
      <AlertRulesView orgId={orgId} canManage={role === "owner" || role === "admin"} />
    </div>
  );
}

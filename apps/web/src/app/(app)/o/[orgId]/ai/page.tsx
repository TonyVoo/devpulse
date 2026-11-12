import type { Metadata } from "next";

import { AiSettingsView } from "@/components/ai/ai-settings";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "AI settings" };

export default async function AiSettingsPage({ params }: PageProps<"/o/[orgId]/ai">) {
  const { orgId } = await params;
  const me = await getMe();
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">AI investigator</h1>
        <p className="text-sm text-fg-muted">
          Evidence-grounded incident analysis. Provider API keys stay on the DevPulse server and are never shown here.
        </p>
      </header>
      <AiSettingsView orgId={orgId} canConfigure={role === "owner" || role === "admin"} />
    </div>
  );
}

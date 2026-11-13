import type { Metadata } from "next";

import { AiSettingsView } from "@/components/ai/ai-settings";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("ai.pageTitle") };
}

export default async function AiSettingsPage({ params }: PageProps<"/o/[orgId]/ai">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("ai.title")}</h1>
        <p className="text-sm text-fg-muted">{t("ai.intro")}</p>
      </header>
      <AiSettingsView orgId={orgId} canConfigure={role === "owner" || role === "admin"} />
    </div>
  );
}

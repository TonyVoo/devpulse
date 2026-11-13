import type { Metadata } from "next";

import { AlertRulesView } from "@/components/alerts/alert-rules";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("alerts.title") };
}

export default async function AlertsPage({ params }: PageProps<"/o/[orgId]/alerts">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("alerts.title")}</h1>
        <p className="mt-1 text-sm text-fg-muted">{t("alerts.intro")}</p>
      </header>
      <AlertRulesView orgId={orgId} canManage={role === "owner" || role === "admin"} />
    </div>
  );
}

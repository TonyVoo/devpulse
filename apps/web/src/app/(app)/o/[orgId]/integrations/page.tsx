import type { Metadata } from "next";

import { IntegrationsView } from "@/components/integrations/integrations-view";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("integrations.title") };
}

export default async function IntegrationsPage({ params }: PageProps<"/o/[orgId]/integrations">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("integrations.title")}</h1>
      </header>
      <IntegrationsView
        orgId={orgId}
        canManage={role === "owner" || role === "admin"}
        apiOrigin={process.env.API_PUBLIC_URL ?? "http://localhost:8000"}
      />
    </div>
  );
}

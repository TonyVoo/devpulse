import type { Metadata } from "next";

import { ServicesView } from "@/components/services/services-view";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("services.title") };
}

export default async function ServicesPage({ params }: PageProps<"/o/[orgId]/services">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("services.title")}</h1>
        <p className="mt-1 text-sm text-fg-muted">{t("services.intro")}</p>
      </header>
      <ServicesView orgId={orgId} canManage={role !== undefined && role !== "viewer"} />
    </div>
  );
}

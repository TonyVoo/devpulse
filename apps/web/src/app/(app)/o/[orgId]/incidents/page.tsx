import type { Metadata } from "next";

import { IncidentsView } from "@/components/incidents/incidents-view";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("incidents.title") };
}

export default async function IncidentsPage({ params }: PageProps<"/o/[orgId]/incidents">) {
  const { orgId } = await params;
  const t = await getT();
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("incidents.title")}</h1>
      </header>
      <IncidentsView orgId={orgId} />
    </div>
  );
}

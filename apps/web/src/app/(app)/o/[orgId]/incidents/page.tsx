import type { Metadata } from "next";

import { IncidentsView } from "@/components/incidents/incidents-view";

export const metadata: Metadata = { title: "Incidents" };

export default async function IncidentsPage({ params }: PageProps<"/o/[orgId]/incidents">) {
  const { orgId } = await params;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Incidents</h1>
      </header>
      <IncidentsView orgId={orgId} />
    </div>
  );
}

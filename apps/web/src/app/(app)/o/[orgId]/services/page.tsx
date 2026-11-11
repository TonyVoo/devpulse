import type { Metadata } from "next";

import { ServicesView } from "@/components/services/services-view";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Services" };

export default async function ServicesPage({ params }: PageProps<"/o/[orgId]/services">) {
  const { orgId } = await params;
  const role = (await getMe()).memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Services</h1>
        <p className="mt-1 text-sm text-fg-muted">Everything DevPulse monitors in this organization.</p>
      </header>
      <ServicesView orgId={orgId} canManage={role !== undefined && role !== "viewer"} />
    </div>
  );
}

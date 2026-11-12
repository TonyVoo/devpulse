import type { Metadata } from "next";

import { ServiceDetail } from "@/components/services/service-detail";
import type { components } from "@/lib/api-types";
import { serverGet } from "@/lib/server-api";

export async function generateMetadata({ params }: PageProps<"/o/[orgId]/services/[serviceId]">): Promise<Metadata> {
  const { orgId, serviceId } = await params;
  try {
    const s = await serverGet<components["schemas"]["ServiceOut"]>(`orgs/${orgId}/services/${serviceId}`);
    return { title: s.name };
  } catch {
    return { title: "Service" };
  }
}

export default async function ServicePage({ params }: PageProps<"/o/[orgId]/services/[serviceId]">) {
  const { orgId, serviceId } = await params;
  return (
    <div className="px-4 py-6 md:px-8 md:py-8">
      <ServiceDetail orgId={orgId} serviceId={serviceId} />
    </div>
  );
}

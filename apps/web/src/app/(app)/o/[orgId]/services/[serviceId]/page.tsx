import type { Metadata } from "next";

import { ServiceDetail } from "@/components/services/service-detail";

export const metadata: Metadata = { title: "Service" };

export default async function ServicePage({ params }: PageProps<"/o/[orgId]/services/[serviceId]">) {
  const { orgId, serviceId } = await params;
  return (
    <div className="px-4 py-6 md:px-8 md:py-8">
      <ServiceDetail orgId={orgId} serviceId={serviceId} />
    </div>
  );
}

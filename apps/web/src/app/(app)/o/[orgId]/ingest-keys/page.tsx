import type { Metadata } from "next";

import { IngestKeysView } from "@/components/services/ingest-keys-view";
import { EmptyState } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Ingest keys" };

export default async function IngestKeysPage({ params }: PageProps<"/o/[orgId]/ingest-keys">) {
  const { orgId } = await params;
  const role = (await getMe()).memberships.find((m) => m.id === orgId)?.role;
  const apiOrigin = process.env.API_PUBLIC_URL ?? "http://localhost:8000";
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Ingest keys</h1>
        <p className="mt-1 text-sm text-fg-muted">
          Credentials your services and CI use to send metrics, logs and deployments.
        </p>
      </header>
      {role === "viewer" ? (
        <EmptyState title="Engineers and admins manage keys" description="Ask an admin if you need a key." />
      ) : (
        <IngestKeysView orgId={orgId} apiOrigin={apiOrigin} />
      )}
    </div>
  );
}

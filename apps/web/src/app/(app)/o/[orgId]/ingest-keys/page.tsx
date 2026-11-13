import type { Metadata } from "next";

import { IngestKeysView } from "@/components/services/ingest-keys-view";
import { EmptyState } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("keys.title") };
}

export default async function IngestKeysPage({ params }: PageProps<"/o/[orgId]/ingest-keys">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  const apiOrigin = process.env.API_PUBLIC_URL ?? "http://localhost:8000";
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("keys.title")}</h1>
        <p className="mt-1 text-sm text-fg-muted">{t("keys.intro")}</p>
      </header>
      {role === "viewer" ? (
        <EmptyState title={t("keys.viewerTitle")} description={t("keys.viewerBody")} />
      ) : (
        <IngestKeysView orgId={orgId} apiOrigin={apiOrigin} />
      )}
    </div>
  );
}

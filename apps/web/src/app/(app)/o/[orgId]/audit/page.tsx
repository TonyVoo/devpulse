import type { Metadata } from "next";

import { AuditLog } from "@/components/audit/audit-log";
import { EmptyState } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("audit.title") };
}

export default async function AuditPage({ params }: PageProps<"/o/[orgId]/audit">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("audit.title")}</h1>
        <p className="mt-1 text-sm text-fg-muted">{t("audit.intro")}</p>
      </header>
      {role === "owner" || role === "admin" ? (
        <AuditLog orgId={orgId} />
      ) : (
        <EmptyState title={t("audit.adminsOnly")} description={t("audit.adminsOnlyBody")} />
      )}
    </div>
  );
}

import type { Metadata } from "next";

import { AuditLog } from "@/components/audit/audit-log";
import { EmptyState } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Audit log" };

export default async function AuditPage({ params }: PageProps<"/o/[orgId]/audit">) {
  const { orgId } = await params;
  const me = await getMe();
  const role = me.memberships.find((m) => m.id === orgId)?.role;
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">Audit log</h1>
        <p className="mt-1 text-sm text-fg-muted">Who changed what, and when. Entries can&apos;t be edited.</p>
      </header>
      {role === "owner" || role === "admin" ? (
        <AuditLog orgId={orgId} />
      ) : (
        <EmptyState title="Admins only" description="Ask an owner or admin if you need to review changes." />
      )}
    </div>
  );
}

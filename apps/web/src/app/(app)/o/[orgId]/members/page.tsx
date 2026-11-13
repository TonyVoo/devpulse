import type { Metadata } from "next";

import { MembersTable } from "@/components/orgs/members-table";
import { getMe } from "@/lib/server-api";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("members.title") };
}

export default async function MembersPage({ params }: PageProps<"/o/[orgId]/members">) {
  const { orgId } = await params;
  const [me, t] = await Promise.all([getMe(), getT()]);
  const role = me.memberships.find((m) => m.id === orgId)?.role ?? "viewer";
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <h1 className="text-2xl font-semibold">{t("members.title")}</h1>
        <p className="mt-1 text-sm text-fg-muted">{t("members.intro")}</p>
      </header>
      <MembersTable orgId={orgId} myUserId={me.id} myRole={role} />
    </div>
  );
}

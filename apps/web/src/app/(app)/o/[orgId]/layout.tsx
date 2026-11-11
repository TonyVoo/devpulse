import { notFound } from "next/navigation";

import { getMe } from "@/lib/server-api";

/** Only render org pages for orgs the user belongs to (the API enforces this too). */
export default async function OrgLayout({ children, params }: LayoutProps<"/o/[orgId]">) {
  const { orgId } = await params;
  const me = await getMe();
  if (!me.memberships.some((m) => m.id === orgId)) notFound();
  return children;
}

import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";

export default async function OrgOverview({ params }: PageProps<"/o/[orgId]">) {
  const { orgId } = await params;
  const org = (await getMe()).memberships.find((m) => m.id === orgId);
  return (
    <div className="space-y-6 px-4 py-6 md:px-8 md:py-8">
      <header>
        <p className="font-mono text-xs uppercase tracking-widest text-fg-subtle">{org?.slug}</p>
        <h1 className="text-2xl font-semibold">{org?.name}</h1>
      </header>
      {/* Honest empty state: services, telemetry and incidents arrive in Phase 2. */}
      <EmptyState
        title="No services connected yet"
        description="Service health, incidents and deployments will appear here once services send telemetry. Service onboarding is the next milestone."
        action={
          <Link href={`/o/${orgId}/members`} className={buttonVariants({ variant: "secondary" })}>
            Invite your team
          </Link>
        }
      />
    </div>
  );
}

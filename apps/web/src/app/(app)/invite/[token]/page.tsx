import type { Metadata } from "next";

import { AcceptInvite } from "@/components/orgs/accept-invite";

export const metadata: Metadata = { title: "Join organization" };

export default async function InvitePage({ params }: PageProps<"/invite/[token]">) {
  const { token } = await params;
  return (
    <div className="mx-auto max-w-md px-4 py-16">
      <AcceptInvite token={token} />
    </div>
  );
}

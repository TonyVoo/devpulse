import type { Metadata } from "next";

import { AcceptInvite } from "@/components/orgs/accept-invite";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("invite.pageTitle") };
}

export default async function InvitePage({ params }: PageProps<"/invite/[token]">) {
  const { token } = await params;
  return (
    <div className="mx-auto max-w-md px-4 py-16">
      <AcceptInvite token={token} />
    </div>
  );
}

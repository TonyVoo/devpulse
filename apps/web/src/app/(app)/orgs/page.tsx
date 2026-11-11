import type { Metadata } from "next";
import Link from "next/link";

import { CreateOrgForm } from "@/components/orgs/create-org-form";
import { Card } from "@/components/ui/card";
import { getMe } from "@/lib/server-api";

export const metadata: Metadata = { title: "Organizations" };

export default async function OrgsPage() {
  const me = await getMe();
  return (
    <div className="mx-auto max-w-2xl space-y-8 px-6 py-10">
      <header>
        <h1 className="text-2xl font-semibold">Organizations</h1>
        <p className="mt-1 text-sm text-fg-muted">
          Each organization keeps its own services, incidents and members.
        </p>
      </header>
      {me.memberships.length > 0 && (
        <ul className="divide-y divide-line rounded-lg border border-line bg-surface">
          {me.memberships.map((o) => (
            <li key={o.id}>
              <Link
                href={`/o/${o.id}`}
                className="flex items-center justify-between px-5 py-4 hover:bg-raised"
              >
                <span>
                  <span className="block text-sm font-medium">{o.name}</span>
                  <span className="font-mono text-xs text-fg-subtle">{o.slug}</span>
                </span>
                <span className="rounded-sm border border-line px-2 py-0.5 text-xs capitalize text-fg-muted">
                  {o.role}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      <Card>
        <h2 className="mb-4 text-base font-semibold">
          {me.memberships.length ? "Create another organization" : "Create your first organization"}
        </h2>
        <CreateOrgForm />
      </Card>
    </div>
  );
}

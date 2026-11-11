"use client";

import Link from "next/link";
import { useParams, usePathname, useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { request } from "@/lib/api-client";
import { cn } from "@/lib/utils";

type Org = { id: string; slug: string; name: string; role: string };

const ORG_NAV = [
  { href: "", label: "Overview" },
  { href: "/members", label: "Members" },
] as const;

export function Shell({
  user,
  orgs,
  children,
}: {
  user: { name: string; email: string };
  orgs: Org[];
  children: ReactNode;
}) {
  const params = useParams<{ orgId?: string }>();
  const pathname = usePathname();
  const router = useRouter();
  const [signingOut, setSigningOut] = useState(false);
  const current = orgs.find((o) => o.id === params.orgId);

  async function signOut() {
    setSigningOut(true);
    await request("/api/auth/logout", { method: "POST" }).catch(() => undefined);
    router.replace("/login");
    router.refresh();
  }

  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 flex-col border-r border-line bg-surface md:flex">
        <div className="px-5 py-5 font-mono text-sm tracking-widest text-fg-muted">
          DEV<span className="text-cyan">PULSE</span>
        </div>
        <label className="mx-3 flex flex-col gap-1 text-xs text-fg-subtle">
          <span className="px-2">Organization</span>
          <select
            aria-label="Switch organization"
            className="min-h-10 rounded-md border border-line bg-canvas px-2 text-sm text-fg"
            value={current?.id ?? ""}
            onChange={(e) => router.push(e.target.value ? `/o/${e.target.value}` : "/orgs")}
          >
            {!current && <option value="">Select…</option>}
            {orgs.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
            <option value="">Manage organizations…</option>
          </select>
        </label>
        {current && (
          <nav aria-label="Organization" className="mt-4 flex flex-col gap-0.5 px-3">
            {ORG_NAV.map((item) => {
              const href = `/o/${current.id}${item.href}`;
              const active = pathname === href;
              return (
                <Link
                  key={item.label}
                  href={href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "rounded-md px-3 py-2 text-sm",
                    active ? "bg-raised text-fg" : "text-fg-muted hover:bg-raised hover:text-fg",
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        )}
        <div className="mt-auto border-t border-line p-4">
          <p className="truncate text-sm text-fg">{user.name}</p>
          <p className="truncate text-xs text-fg-subtle">{user.email}</p>
          <Button variant="ghost" size="sm" className="mt-2 -ml-3" onClick={signOut} loading={signingOut}>
            Sign out
          </Button>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Compact bar for narrow screens, where the sidebar is hidden. */}
        <header className="flex items-center gap-3 border-b border-line bg-surface px-4 py-2 md:hidden">
          <span className="font-mono text-xs tracking-widest text-fg-muted">
            DEV<span className="text-cyan">PULSE</span>
          </span>
          <select
            aria-label="Switch organization"
            className="min-h-10 min-w-0 flex-1 rounded-md border border-line bg-canvas px-2 text-sm text-fg"
            value={current?.id ?? ""}
            onChange={(e) => router.push(e.target.value ? `/o/${e.target.value}` : "/orgs")}
          >
            {!current && <option value="">Select…</option>}
            {orgs.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
            <option value="">Manage organizations…</option>
          </select>
          <Button variant="ghost" size="sm" onClick={signOut} loading={signingOut}>
            Sign out
          </Button>
        </header>
        {current && (
          <nav aria-label="Organization" className="flex gap-1 border-b border-line px-3 py-1 md:hidden">
            {ORG_NAV.map((item) => {
              const href = `/o/${current.id}${item.href}`;
              return (
                <Link
                  key={item.label}
                  href={href}
                  aria-current={pathname === href ? "page" : undefined}
                  className={cn(
                    "rounded-md px-3 py-2 text-sm",
                    pathname === href ? "bg-raised text-fg" : "text-fg-muted",
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        )}
        <main className="min-w-0 flex-1">{children}</main>
      </div>
    </div>
  );
}

"use client";

import Link from "next/link";
import { useParams, usePathname, useRouter } from "next/navigation";
import { type ReactNode, useEffect, useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { LanguageSwitcher } from "@/components/ui/language-switcher";
import { Select } from "@/components/ui/select";
import { request } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n/client";
import type { MessageKey } from "@/lib/i18n/translate";
import { cn } from "@/lib/utils";

type Org = { id: string; slug: string; name: string; role: string };

const ORG_NAV: { href: string; label: MessageKey }[] = [
  { href: "", label: "nav.overview" },
  { href: "/services", label: "nav.services" },
  { href: "/incidents", label: "nav.incidents" },
  { href: "/alerts", label: "nav.alerts" },
  { href: "/ai", label: "nav.ai" },
  { href: "/integrations", label: "nav.integrations" },
  { href: "/ingest-keys", label: "nav.ingestKeys" },
  { href: "/members", label: "nav.members" },
  { href: "/audit", label: "nav.audit" },
];

/** Section is active on its own page and on nested pages (e.g. an incident). */
export function isActive(pathname: string, href: string, base: string): boolean {
  const full = `${base}${href}`;
  return pathname === full || (href !== "" && pathname.startsWith(`${full}/`));
}

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
  const { t } = useI18n();
  const [signingOut, setSigningOut] = useState(false);
  const current = orgs.find((o) => o.id === params.orgId);
  const mobileNav = useRef<HTMLElement>(null);
  // On phones the section tabs scroll sideways: keep the current one visible.
  useEffect(() => {
    mobileNav.current
      ?.querySelector('[aria-current="page"]')
      ?.scrollIntoView({ block: "nearest", inline: "center" });
  }, [pathname]);

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
          <span className="px-2">{t("nav.organization")}</span>
          <Select
            aria-label={t("nav.switchOrg")}
            value={current?.id ?? ""}
            onChange={(e) => router.push(e.target.value ? `/o/${e.target.value}` : "/orgs")}
          >
            {!current && <option value="">{t("nav.selectOrg")}</option>}
            {orgs.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
            <option value="">{t("nav.manageOrgs")}</option>
          </Select>
        </label>
        {current && (
          <nav aria-label={t("nav.organization")} className="mt-4 flex flex-col gap-0.5 px-3">
            {ORG_NAV.map((item) => {
              const href = `/o/${current.id}${item.href}`;
              const active = isActive(pathname, item.href, `/o/${current.id}`);
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
                  {t(item.label)}
                </Link>
              );
            })}
          </nav>
        )}
        <div className="mt-auto border-t border-line p-4">
          <p className="truncate text-sm text-fg">{user.name}</p>
          <p className="truncate text-xs text-fg-subtle">{user.email}</p>
          <div className="mt-2 flex items-center justify-between gap-2">
            <Button variant="ghost" size="sm" className="-ml-3" onClick={signOut} loading={signingOut}>
              {t("nav.signOut")}
            </Button>
            <LanguageSwitcher />
          </div>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Compact bar for narrow screens, where the sidebar is hidden. */}
        <header className="flex items-center gap-3 border-b border-line bg-surface px-4 py-2 md:hidden">
          <span className="font-mono text-xs tracking-widest text-fg-muted max-[400px]:hidden">
            DEV<span className="text-cyan">PULSE</span>
          </span>
          <Select
            aria-label={t("nav.switchOrg")}
            className="flex-1"
            value={current?.id ?? ""}
            onChange={(e) => router.push(e.target.value ? `/o/${e.target.value}` : "/orgs")}
          >
            {!current && <option value="">{t("nav.selectOrg")}</option>}
            {orgs.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
            <option value="">{t("nav.manageOrgs")}</option>
          </Select>
          <LanguageSwitcher compact />
          <Button variant="ghost" size="sm" onClick={signOut} loading={signingOut}>
            {t("nav.signOut")}
          </Button>
        </header>
        {current && (
          <nav
            ref={mobileNav}
            aria-label={t("nav.organization")}
            className="flex gap-1 overflow-x-auto whitespace-nowrap border-b border-line px-3 py-1 md:hidden"
          >
            {ORG_NAV.map((item) => {
              const href = `/o/${current.id}${item.href}`;
              const active = isActive(pathname, item.href, `/o/${current.id}`);
              return (
                <Link
                  key={item.label}
                  href={href}
                  aria-current={active ? "page" : undefined}
                  className={cn("shrink-0 rounded-md px-3 py-2 text-sm", active ? "bg-raised text-fg" : "text-fg-muted")}
                >
                  {t(item.label)}
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

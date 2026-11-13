import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/card";
import { getT } from "@/lib/i18n/server";

export default async function NotFound() {
  const t = await getT();
  return (
    <main className="mx-auto max-w-lg px-4 py-24">
      <EmptyState
        title={t("notFound.title")}
        description={t("notFound.body")}
        action={
          <Link href="/" className={buttonVariants({ variant: "secondary" })}>
            {t("notFound.home")}
          </Link>
        }
      />
    </main>
  );
}

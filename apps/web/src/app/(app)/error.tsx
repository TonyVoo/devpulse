"use client";

import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/card";
import { useI18n } from "@/lib/i18n/client";

export default function AppError({ reset }: { error: Error; reset: () => void }) {
  const { t } = useI18n();
  return (
    <div className="p-8">
      <EmptyState
        title={t("errors.pageTitle")}
        description={t("errors.pageBody")}
        action={
          <Button variant="secondary" onClick={reset}>
            {t("common.tryAgain")}
          </Button>
        }
      />
    </div>
  );
}

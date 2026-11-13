"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { Alert, Card } from "@/components/ui/card";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";
import { useI18n } from "@/lib/i18n/client";
import { errorText } from "@/lib/i18n/errors";

type Accepted = components["schemas"]["InvitationAcceptOut"];

/** Joining is an explicit click, never automatic on page load. */
export function AcceptInvite({ token }: { token: string }) {
  const router = useRouter();
  const { t } = useI18n();
  const accept = useMutation({
    mutationFn: () => api.post<Accepted>(`invitations/${encodeURIComponent(token)}/accept`),
    onSuccess: (r) => {
      router.replace(`/o/${r.org.id}`);
      router.refresh();
    },
  });
  const code = accept.error instanceof ApiError ? accept.error.problem.code : null;
  return (
    <Card className="space-y-4">
      <h1 className="text-xl font-semibold">{t("invite.title")}</h1>
      <p className="text-sm text-fg-muted">{t("invite.body")}</p>
      {accept.isError && (
        <Alert>
          {code === "invitation.already_member"
            ? t("invite.alreadyMember")
            : code === "invitation.invalid"
              ? t("invite.invalid")
              : errorText(accept.error, t)}
        </Alert>
      )}
      <Button onClick={() => accept.mutate()} loading={accept.isPending}>
        {t("invite.join")}
      </Button>
    </Card>
  );
}

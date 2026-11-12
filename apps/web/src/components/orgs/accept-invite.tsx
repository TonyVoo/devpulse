"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { Alert, Card } from "@/components/ui/card";
import { api, ApiError } from "@/lib/api-client";
import type { components } from "@/lib/api-types";

type Accepted = components["schemas"]["InvitationAcceptOut"];

/** Joining is an explicit click, never automatic on page load. */
export function AcceptInvite({ token }: { token: string }) {
  const router = useRouter();
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
      <h1 className="text-xl font-semibold">You&apos;ve been invited to an organization</h1>
      <p className="text-sm text-fg-muted">
        The invitation must match the email address you&apos;re signed in with.
      </p>
      {accept.isError && (
        <Alert>
          {code === "invitation.already_member"
            ? "You're already a member of this organization."
            : code === "invitation.invalid"
              ? "This invitation is invalid, expired, revoked, or meant for a different email address."
              : accept.error.message}
        </Alert>
      )}
      <Button onClick={() => accept.mutate()} loading={accept.isPending}>
        Join organization
      </Button>
    </Card>
  );
}

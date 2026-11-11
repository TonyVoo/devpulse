"use client";

import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/card";

export default function AppError({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="p-8">
      <EmptyState
        title="Couldn't load this page"
        description="DevPulse couldn't reach its API. Your session is intact. Try again in a moment."
        action={
          <Button variant="secondary" onClick={reset}>
            Try again
          </Button>
        }
      />
    </div>
  );
}

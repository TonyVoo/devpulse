import type { HTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/utils";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("rounded-lg border border-line bg-surface p-6", className)} {...props} />;
}

export function Alert({
  tone = "error",
  children,
  className,
}: {
  tone?: "error" | "info";
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      className={cn(
        "rounded-md border px-3 py-2 text-sm",
        tone === "error"
          ? "border-critical/40 bg-critical/10 text-fg"
          : "border-cyan/30 bg-cyan/10 text-fg",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed border-line px-6 py-12 text-center">
      <h2 className="text-base font-semibold text-fg">{title}</h2>
      <p className="max-w-md text-sm text-fg-muted">{description}</p>
      {action && <div className="mt-3">{action}</div>}
    </div>
  );
}

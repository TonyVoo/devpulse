import { cva, type VariantProps } from "class-variance-authority";
import type { ButtonHTMLAttributes } from "react";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium transition-colors " +
    "disabled:pointer-events-none disabled:opacity-50 min-h-10 px-4",
  {
    variants: {
      variant: {
        primary: "bg-cyan text-on-accent hover:bg-cyan/90",
        secondary: "border border-line bg-surface text-fg hover:bg-raised",
        ghost: "text-fg-muted hover:bg-raised hover:text-fg",
        destructive: "bg-critical text-white hover:bg-critical/90",
      },
      size: { sm: "min-h-8 px-3 text-xs", md: "", lg: "min-h-12 px-6 text-base" },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants> & { loading?: boolean };

export function Button({ className, variant, size, loading, children, disabled, ...props }: ButtonProps) {
  return (
    <button
      className={cn(buttonVariants({ variant, size }), className)}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...props}
    >
      {loading && (
        <span
          aria-hidden
          className="size-3.5 animate-spin rounded-full border-2 border-current border-r-transparent"
        />
      )}
      {children}
    </button>
  );
}

export { buttonVariants };

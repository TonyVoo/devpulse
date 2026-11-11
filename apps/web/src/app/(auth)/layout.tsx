import { Card } from "@/components/ui/card";

export default function AuthLayout({ children }: LayoutProps<"/">) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[radial-gradient(ellipse_at_top,rgba(34,211,238,0.10),transparent_60%)] px-4">
      <div className="w-full max-w-sm">
        <p className="mb-6 text-center font-mono text-sm tracking-widest text-fg-muted">
          DEV<span className="text-cyan">PULSE</span>
        </p>
        <Card>{children}</Card>
      </div>
    </main>
  );
}

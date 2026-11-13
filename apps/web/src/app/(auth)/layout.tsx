import { Card } from "@/components/ui/card";
import { LanguageSwitcher } from "@/components/ui/language-switcher";

export default function AuthLayout({ children }: LayoutProps<"/">) {
  return (
    <main className="relative flex min-h-screen items-center justify-center bg-[radial-gradient(ellipse_at_top,rgba(34,211,238,0.10),transparent_60%)] px-4">
      <LanguageSwitcher className="absolute right-4 top-4" />
      <div className="w-full max-w-sm">
        <p className="mb-6 text-center font-mono text-sm tracking-widest text-fg-muted">
          DEV<span className="text-cyan">PULSE</span>
        </p>
        <Card>{children}</Card>
      </div>
    </main>
  );
}

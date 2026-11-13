import type { Metadata } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import { connection } from "next/server";

import { Providers } from "@/components/providers";
import { getLocale, getT } from "@/lib/i18n/server";

import "./globals.css";

// The Vietnamese subset carries the diacritics (ă, ơ, ư, ạ, ế…); without it they fall back.
const inter = Inter({ variable: "--font-inter", subsets: ["latin", "vietnamese"] });
const mono = JetBrains_Mono({ variable: "--font-jetbrains-mono", subsets: ["latin", "vietnamese"] });

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: { default: "DevPulse", template: "%s · DevPulse" },
    description: t("meta.description"),
  };
}

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // Render every page per request: the CSP nonce (src/proxy.ts) must be fresh for each
  // response, and a prerendered page would ship scripts without it.
  await connection();
  const locale = await getLocale();
  return (
    <html lang={locale} className={`${inter.variable} ${mono.variable} h-full antialiased`}>
      <body className="min-h-full">
        <Providers locale={locale}>{children}</Providers>
      </body>
    </html>
  );
}

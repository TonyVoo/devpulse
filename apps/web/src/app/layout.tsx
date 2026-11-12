import type { Metadata } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import { connection } from "next/server";

import { Providers } from "@/components/providers";

import "./globals.css";

const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });
const mono = JetBrains_Mono({ variable: "--font-jetbrains-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "DevPulse", template: "%s · DevPulse" },
  description: "Engineering observability, incidents and AI investigation.",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // Render every page per request: the CSP nonce (src/proxy.ts) must be fresh for each
  // response, and a prerendered page would ship scripts without it.
  await connection();
  return (
    <html lang="en" className={`${inter.variable} ${mono.variable} h-full antialiased`}>
      <body className="min-h-full">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

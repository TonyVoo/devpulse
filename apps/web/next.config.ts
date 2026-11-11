import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cache Components / Partial Prefetching are disabled for now: every dashboard page is
  // per-user and session-dependent, so there is little static shell to prerender and the
  // Suspense-everywhere requirement adds complexity. Revisit in Phase 5 (DECISIONS.md ADR-013).
  cacheComponents: false,
  output: "standalone",
  poweredByHeader: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },
};

export default nextConfig;

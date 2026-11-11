# DevPulse web dashboard

Next.js 16 App Router app with a server-side BFF: tokens live in httpOnly cookies and the
browser only talks to same-origin routes. See the repository README and docs/ARCHITECTURE.md.

```bash
pnpm dev        # http://localhost:3000 (needs the API: `make up` from the repo root)
pnpm test       # vitest
pnpm e2e        # playwright (needs `pnpm exec playwright install chromium` once)
```

import { defineConfig, devices } from "@playwright/test";

/**
 * Critical-flow E2E tests. They run against a real API (start it with `make up`) and a
 * Next server started here. Browsers: `pnpm exec playwright install chromium`.
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3100",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "pnpm build && pnpm start --port 3100",
        url: "http://localhost:3100/login",
        timeout: 180_000,
        reuseExistingServer: !process.env.CI,
        env: {
          API_INTERNAL_URL: process.env.API_INTERNAL_URL ?? "http://localhost:8000",
          SESSION_COOKIE_SECURE: "false",
        },
      },
});

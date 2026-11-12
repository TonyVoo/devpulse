import { expect, test } from "@playwright/test";

import { createOrg, registerUser } from "./support";

test("pages ship a nonce CSP and run without CSP violations", async ({ page }) => {
  const violations: string[] = [];
  page.on("console", (m) => {
    if (m.type() === "error" && /Content Security Policy|CSP/i.test(m.text())) violations.push(m.text());
  });

  const login = await page.goto("/login");
  const csp = login!.headers()["content-security-policy"];
  expect(csp).toMatch(/script-src 'self' 'nonce-[^']+' 'strict-dynamic'/);
  expect(csp).toContain("frame-ancestors 'none'");
  expect(login!.headers()["x-frame-options"]).toBe("DENY");

  // Hydration needs the nonce on Next's scripts: if it were missing, the form wouldn't work.
  await registerUser(page, "Csp Checker");
  const orgId = await createOrg(page, "CSP Org");
  for (const path of ["", "/incidents", "/alerts", "/services", "/members", "/audit"]) {
    await page.goto(`/o/${orgId}${path}`);
    await expect(page.locator("main")).toBeVisible();
  }
  expect(violations).toEqual([]);
});

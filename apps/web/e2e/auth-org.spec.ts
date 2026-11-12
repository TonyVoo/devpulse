import { expect, test } from "@playwright/test";

// Test-only credentials for a throwaway account created by this test run.
const PASSWORD = "devpulse-e2e-password";

test("register → create org → see membership → sign out → sign in", async ({ page, context }) => {
  const email = `e2e-${Date.now()}-${Math.floor(Math.random() * 1e6)}@example.com`;

  // Protected pages redirect to login and remember where you were going.
  await page.goto("/orgs");
  await expect(page).toHaveURL(/\/login\?next=%2Forgs/);

  await page.getByRole("link", { name: "Create an account" }).click();
  await page.getByLabel("Name").fill("E2E Owner");
  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page).toHaveURL(/\/orgs$/);

  // Tokens are httpOnly; only the CSRF cookie is visible to scripts.
  const cookies = await context.cookies();
  expect(cookies.find((c) => c.name === "dp_rt")?.httpOnly).toBe(true);
  expect(cookies.find((c) => c.name === "dp_at")?.httpOnly).toBe(true);
  expect(await page.evaluate(() => document.cookie)).not.toContain("dp_rt");

  await page.getByLabel("Organization name").fill("E2E Org");
  await page.getByRole("button", { name: "Create organization" }).click();
  await expect(page.getByRole("heading", { name: "E2E Org" })).toBeVisible();

  await page.getByRole("link", { name: "Members" }).click();
  const row = page.getByRole("row", { name: /E2E Owner/ });
  await expect(row).toContainText("Owner");

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login/);

  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "E2E Org" })).toBeVisible();
});

test("wrong password shows an error and stays on login", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Work email").fill("nobody@example.com");
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  // (Next.js's route announcer is also role="alert"; target the form's message.)
  await expect(page.getByRole("alert").filter({ hasText: "Email or password is incorrect" })).toBeVisible();
  await expect(page).toHaveURL(/\/login/);
});

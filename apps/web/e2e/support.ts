import AxeBuilder from "@axe-core/playwright";
import { expect, type Page } from "@playwright/test";

// Test-only credentials for throwaway accounts created by these runs.
export const PASSWORD = "devpulse-e2e-password";

export function uniqueEmail(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}@example.com`;
}

export async function registerUser(page: Page, name: string, email = uniqueEmail("e2e")): Promise<string> {
  await page.goto("/register");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page).toHaveURL(/\/orgs$/);
  return email;
}

/** Creates an org through the UI; returns its id (from the URL). */
export async function createOrg(page: Page, name: string): Promise<string> {
  await page.getByLabel("Organization name").fill(name);
  await page.getByRole("button", { name: "Create organization" }).click();
  await expect(page.getByRole("heading", { name })).toBeVisible();
  return new URL(page.url()).pathname.split("/")[2];
}

/** Calls the BFF from the page (session cookie + CSRF header), like the app does. */
export async function apiCall<T>(page: Page, method: string, path: string, body?: unknown): Promise<T> {
  return page.evaluate(
    async ({ method, path, body }) => {
      const csrf = document.cookie.split("; ").find((c) => c.startsWith("dp_csrf="))?.slice(8);
      const res = await fetch(`/api/v1/${path}`, {
        method,
        headers: { "content-type": "application/json", ...(csrf ? { "x-csrf-token": csrf } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${await res.text()}`);
      return res.status === 204 ? null : res.json();
    },
    { method, path, body },
  ) as Promise<T>;
}

/** No serious or critical WCAG 2.x A/AA violations on the current page, in light and dark. */
export async function expectAccessible(page: Page, label: string): Promise<void> {
  for (const colorScheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme });
    await page.waitForTimeout(400); // let colour transitions finish before measuring contrast
    const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
    const bad = results.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
    expect(
      bad.map((v) => `${v.id}: ${v.help} (${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")})`),
      `accessibility violations on ${label} (${colorScheme})`,
    ).toEqual([]);
  }
  await page.emulateMedia({ colorScheme: "light" });
}

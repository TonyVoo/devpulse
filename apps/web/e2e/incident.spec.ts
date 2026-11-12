import { expect, test } from "@playwright/test";

import { apiCall, createOrg, expectAccessible, registerUser } from "./support";

test("incident: open → acknowledge → comment; AI is off until enabled", async ({ page }) => {
  await registerUser(page, "Oncall Olu");
  const orgId = await createOrg(page, "Incident Org");
  const inc = await apiCall<{ key: string }>(page, "POST", `orgs/${orgId}/incidents`, {
    title: "Checkout returning 500s",
    severity: "sev2",
  });

  await page.goto(`/o/${orgId}/incidents`);
  await page.getByRole("link", { name: "Checkout returning 500s" }).click();
  await expect(page.getByRole("heading", { name: "Checkout returning 500s" })).toBeVisible();
  await expect(page.getByText(/^triggered$/i)).toBeVisible();
  await expect(page.getByText(/isn't linked to a service/)).toBeVisible(); // honest empty state
  await expectAccessible(page, "incident detail");

  await page.getByRole("button", { name: "Acknowledge" }).click();
  await expect(page.getByText(/^acknowledged$/i)).toBeVisible();
  await expect(page.getByRole("button", { name: "Acknowledge" })).toHaveCount(0);
  await expect(page.getByText("Oncall Olu acknowledged")).toBeVisible(); // timeline

  await page.getByLabel("Add a comment").fill("Rolling back the last release.");
  await page.getByRole("button", { name: "Comment" }).click();
  await expect(page.getByText("Rolling back the last release.")).toBeVisible();

  await page.getByRole("button", { name: "Investigate with AI" }).click();
  await expect(page.getByText(/turned off for this organization/)).toBeVisible();
  expect(inc.key).toMatch(/^INC-\d+$/);
});

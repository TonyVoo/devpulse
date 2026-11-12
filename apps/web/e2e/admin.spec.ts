import { expect, test } from "@playwright/test";

import { createOrg, expectAccessible, registerUser, uniqueEmail } from "./support";

test("admin: service → alert rule with preview → GitHub → invite → audit log", async ({ page, browser }) => {
  await registerUser(page, "Admin Ada");
  const orgId = await createOrg(page, "Admin Org");
  await expectAccessible(page, "overview");

  // Service
  await page.getByRole("link", { name: "Services" }).first().click();
  await page.getByRole("button", { name: "Add service" }).click();
  await page.getByLabel("Name").fill("Checkout");
  await page.getByRole("button", { name: "Create service" }).click();
  await expect(page.getByRole("link", { name: "Checkout" })).toBeVisible();
  await expectAccessible(page, "services");
  await page.getByRole("link", { name: "Checkout" }).click();
  await expect(page.getByRole("heading", { name: "Checkout" })).toBeVisible();
  await expect(page.getByText("No data in this range").first()).toBeVisible(); // no fake data
  await expectAccessible(page, "service detail");

  // Alert rule with live preview
  await page.goto(`/o/${orgId}/alerts`);
  await page.getByRole("button", { name: "New alert rule" }).click();
  await page.getByLabel("Name").fill("Checkout p95 latency");
  await page.getByLabel("Threshold").fill("750");
  await expect(page.getByText("p95(http.server.duration_ms) over 5 min > 750 ms for 2 min")).toBeVisible();
  await expect(page.getByText("Would not have fired in the last 6 hours.")).toBeVisible();
  await expectAccessible(page, "alert rule builder");
  await page.getByRole("button", { name: "Create rule" }).click();
  await expect(page.getByText("Checkout p95 latency")).toBeVisible();
  await page.getByRole("button", { name: "Disable" }).click();
  await expect(page.getByText("Disabled")).toBeVisible();

  // GitHub integration: secret shown once
  await page.goto(`/o/${orgId}/integrations`);
  await page.getByRole("button", { name: "Create webhook" }).click();
  await expect(page.getByText("Payload URL")).toBeVisible();
  await expect(page.getByText(/\/webhooks\/github\//).first()).toBeVisible();
  await expectAccessible(page, "integrations");

  // Invite link → another user joins
  await page.goto(`/o/${orgId}/members`);
  const inviteeEmail = uniqueEmail("invitee");
  await page.getByLabel("Email").fill(inviteeEmail);
  await page.getByRole("button", { name: "Create invite link" }).click();
  const link = (await page.locator("code", { hasText: "/invite/" }).textContent())!.trim();
  await expect(page.getByText(inviteeEmail)).toBeVisible(); // pending invitations
  await expectAccessible(page, "members");

  const other = await browser.newContext();
  const p2 = await other.newPage();
  await registerUser(p2, "Ivo Invitee", inviteeEmail);
  await p2.goto(new URL(link).pathname);
  await expectAccessible(p2, "accept invite");
  await p2.getByRole("button", { name: "Join organization" }).click();
  await expect(p2.getByRole("heading", { name: "Admin Org" })).toBeVisible();
  await other.close();

  // Role change, then the audit log shows who did what
  await page.reload();
  await page.getByLabel("Role for Ivo Invitee").selectOption("viewer");
  await expect(page.getByLabel("Role for Ivo Invitee")).toHaveValue("viewer");

  await page.goto(`/o/${orgId}/audit`);
  for (const action of ["member.role_changed", "member.joined", "integration.created", "alert_rule.updated", "alert_rule.created", "service.created"]) {
    await expect(page.getByText(action, { exact: true }).first()).toBeVisible();
  }
  await page.getByLabel("Show").selectOption("Members");
  await expect(page.getByText("alert_rule.created")).toHaveCount(0);
  await page.getByRole("button", { name: /Show changes \(role\)/ }).first().click();
  await expect(page.getByRole("cell", { name: "viewer" })).toBeVisible();
  await expectAccessible(page, "audit log");
});

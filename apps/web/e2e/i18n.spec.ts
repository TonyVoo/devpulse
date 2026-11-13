import { expect, test } from "@playwright/test";

import { expectAccessible, PASSWORD, uniqueEmail } from "./support";

test("Vietnamese: browser preference, switching, and the app in Vietnamese", async ({ browser }) => {
  // A browser that prefers Vietnamese gets Vietnamese without choosing anything.
  const context = await browser.newContext({ locale: "vi-VN" });
  const page = await context.newPage();
  await page.goto("/login");
  await expect(page.getByRole("heading", { name: "Đăng nhập DevPulse" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "vi");
  await expectAccessible(page, "login (vi)");

  // Switching to English is remembered (cookie) and wins over the browser preference.
  await page.getByRole("radio", { name: "English" }).click();
  await expect(page.getByRole("heading", { name: "Sign in to DevPulse" })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Sign in to DevPulse" })).toBeVisible();

  // Back to Vietnamese, then register and use the app.
  await page.getByRole("radio", { name: "Tiếng Việt" }).click();
  await page.getByRole("link", { name: "Tạo tài khoản" }).click();
  await page.getByLabel("Họ tên").fill("Người dùng E2E");
  await page.getByLabel("Email công việc").fill(uniqueEmail("e2e-vi"));
  await page.getByLabel("Mật khẩu").fill(PASSWORD);
  await page.getByRole("button", { name: "Tạo tài khoản" }).click();
  await expect(page).toHaveURL(/\/orgs$/, { timeout: 15_000 });
  await expect(page.getByRole("heading", { name: "Tổ chức", exact: true })).toBeVisible();

  await page.getByLabel("Tên tổ chức").fill("Tổ chức E2E");
  await page.getByRole("button", { name: "Tạo tổ chức" }).click();
  await expect(page.getByRole("heading", { name: "Tổ chức E2E" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Chưa kết nối dịch vụ nào" })).toBeVisible();
  await expect(page).toHaveTitle("Tổng quan · DevPulse");
  await expectAccessible(page, "overview (vi)");

  await page.getByRole("navigation", { name: "Tổ chức" }).getByRole("link", { name: "Thành viên" }).click();
  await expect(page.getByRole("heading", { name: "Thành viên" })).toBeVisible();
  await expect(page.getByRole("row", { name: /Người dùng E2E/ })).toContainText("Chủ sở hữu");
  await context.close();
});

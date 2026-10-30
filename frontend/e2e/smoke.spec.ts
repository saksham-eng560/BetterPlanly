import { type Page, expect, test } from "@playwright/test";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "../..");
const SHOTS = path.join(ROOT, "docs", "screenshots");
const NOW = new Date("2026-10-30T10:05:00");

async function open(page: Page) {
  await page.clock.setFixedTime(NOW);
  await page.goto("/");
}

test("import a plan, see the day, tick, move, ask the agent", async ({ page }) => {
  await open(page);

  // import the sample plan through the sheet
  await page.getByRole("button", { name: "Import" }).click();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Choose File…" }).click();
  await (await chooser).setFiles(path.join(ROOT, "examples", "sample-plan.json"));
  await expect(page.getByRole("status").filter({ hasText: "Late October sprint" }).first()).toBeVisible();
  await page.screenshot({ path: path.join(SHOTS, "import.png") });
  await page.getByRole("button", { name: "Close" }).click();

  // the day: type-coded cards on the timeline
  await expect(page.locator(".task-card", { hasText: "DSA practice — graphs" })).toBeVisible();

  // first open with a missed task → the agent reviews the day and re-plans it into today
  await expect(page.locator(".event-chip", { hasText: "1 missed task" })).toBeVisible({ timeout: 20_000 });
  await expect(page.locator(".changes-card")).toBeVisible({ timeout: 20_000 });
  await expect(page.getByRole("region", { name: "Missed" })).toHaveCount(0);
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(SHOTS, "today-light.png") });

  // tick a task in the checklist → undo toast, then the agent reacts
  await page.getByRole("checkbox", { name: "Complete “Evening journal”" }).check({ force: true });
  await expect(page.getByRole("status").filter({ hasText: "Completed “Evening journal”" })).toBeVisible();
  await expect(page.locator(".event-chip", { hasText: "Completed" })).toBeVisible({ timeout: 15_000 });

  // move a task to tomorrow from its row menu
  await page.getByRole("button", { name: "Move “Groceries”" }).click();
  await page.getByRole("button", { name: /^Tomorrow/ }).click();
  await expect(page.getByRole("status").filter({ hasText: "Moved “Groceries” to Tomorrow" })).toBeVisible();
  await expect(page.locator(".task-card", { hasText: "Groceries" })).toHaveCount(0);

  // undo the move from the toast
  await page.getByRole("status").filter({ hasText: "Moved “Groceries”" }).getByRole("button", { name: "Undo" }).click();
  await expect(page.locator(".task-card", { hasText: "Groceries" })).toBeVisible();

  // checklist section and a task's detail sheet
  await page.locator(".checklist").scrollIntoViewIfNeeded();
  await page.screenshot({ path: path.join(SHOTS, "checklist-light.png") });
  await page.getByRole("button", { name: "Details and resources for “Build Planly task API”" }).click();
  await expect(page.getByRole("dialog", { name: "Build Planly task API" })).toBeVisible();
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(SHOTS, "task-sheet.png") });
});

test("dark mode and phone layout", async ({ browser }) => {
  const dark = await browser.newPage({ colorScheme: "dark", viewport: { width: 1440, height: 960 } });
  await open(dark);
  await expect(dark.locator(".task-card").first()).toBeVisible();
  await dark.waitForTimeout(600);
  await dark.screenshot({ path: path.join(SHOTS, "today-dark.png") });

  const phone = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  await open(phone);
  await expect(phone.locator(".task-card").first()).toBeVisible();
  await phone.screenshot({ path: path.join(SHOTS, "phone.png") });
  await phone.getByRole("button", { name: "Open the agent" }).click();
  await expect(phone.getByRole("complementary", { name: "Planly agent" })).toBeInViewport();
  await phone.waitForTimeout(400);
  await phone.screenshot({ path: path.join(SHOTS, "phone-agent.png") });
});

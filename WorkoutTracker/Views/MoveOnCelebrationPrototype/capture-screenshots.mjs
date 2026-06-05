import { chromium } from "/Users/sunny/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs";

const port = process.argv[2] ?? "4174";
const baseUrl = `http://127.0.0.1:${port}`;
const variants = ["F3", "C2", "E2", "F2", "H"];

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 430, height: 932 },
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true
});

for (const variant of variants) {
  await page.goto(`${baseUrl}/?variant=${variant}`, { waitUntil: "networkidle" });
  await page.waitForTimeout(1100);
  await page.screenshot({
    path: `WorkoutTracker/Views/MoveOnCelebrationPrototype/screenshots/move-on-celebration-${variant}.png`,
    fullPage: false
  });
}

await browser.close();

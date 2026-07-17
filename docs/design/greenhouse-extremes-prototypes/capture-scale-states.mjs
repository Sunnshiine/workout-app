// THROWAWAY PROTOTYPE tooling — issue #435.
// prototype:capture shoots one PNG per variant at the page's default state
// (days=6). This ad-hoc companion captures the other day-count state the
// round needs (days=3) for every variant, per the capture script's own
// "drive multi-state ad hoc" guidance. Run from the repo root:
//
//   node docs/design/greenhouse-extremes-prototypes/capture-scale-states.mjs
import { chromium, devices } from "playwright";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const base = process.argv[2] ?? "block-grid-scale";
const dayStates = (process.argv[3] ?? "3").split(",").map(Number);
const html = pathToFileURL(resolve(HERE, `${base}.html`));
const browser = await chromium.launch();
const ctx = await browser.newContext(devices["iPhone 15 Pro"]);
const page = await ctx.newPage();
for (const variant of ["a", "b", "c", "d", "e"]) {
  for (const days of dayStates) {
    await page.goto(`${html}?variant=${variant}&days=${days}`);
    await page.waitForTimeout(250);
    const out = resolve(HERE, `${base}-${variant}-${days}d.png`);
    await page.screenshot({ path: out, fullPage: true });
    console.log(`captured ${out}`);
  }
}
await browser.close();

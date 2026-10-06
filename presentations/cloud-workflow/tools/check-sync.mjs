// Proves the presenter window and the audience window drive each other, and the stage letterboxes.
// Usage: node tools/check-sync.mjs <harness dir>
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const harness = resolve(process.argv[2]);
const { chromium } = createRequire(`${harness}/package.json`)('playwright-core');
const deck = pathToFileURL(resolve(fileURLToPath(import.meta.url), '../../index.html')).href;
const active = (p) => p.evaluate(() => [...document.querySelectorAll('section.slide')].findIndex((s) => s.classList.contains('active')) + 1);
const failures = [];
const expect = (ok, what) => { console.log(ok ? 'ok  ' : 'FAIL', what); if (!ok) failures.push(what); };

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const presenter = await ctx.newPage();
await presenter.goto(`${deck}?presenter#1`);
const [audience] = await Promise.all([ctx.waitForEvent('page'), presenter.click('[data-open]')]);
await audience.waitForLoadState();
await audience.waitForTimeout(300);
expect(await active(audience) === 1, 'audience opens on the presenter slide');
await presenter.keyboard.press('ArrowRight');
await audience.waitForTimeout(300);
expect(await active(audience) === 2, 'presenter ArrowRight moves the audience to 2');
await audience.keyboard.press('Space');
await presenter.waitForTimeout(300);
expect(await active(presenter) === 3, 'audience Space moves the presenter to 3');
expect((await presenter.textContent('.count')).startsWith('3 / '), 'presenter counter follows');
await presenter.keyboard.press('PageUp');
await audience.waitForTimeout(300);
expect(await active(audience) === 2, 'clicker PageUp goes back in both');

for (const [w, h] of [[1280, 800], [1366, 768], [3840, 2160]]) {
  const p = await browser.newPage({ viewport: { width: w, height: h } });
  await p.goto(`${deck}#2`);
  const r = await p.evaluate(() => { const b = document.querySelector('.deck').getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; });
  const fits = r[0] >= -0.5 && r[1] >= -0.5 && r[0] + r[2] <= w + 0.5 && r[1] + r[3] <= h + 0.5 && Math.abs(r[2] / r[3] - 16 / 9) < 0.01;
  expect(fits, `stage letterboxes inside ${w}x${h} at 16:9 (${r.map(Math.round).join(',')})`);
  await p.close();
}
await browser.close();
process.exit(failures.length ? 1 : 0);

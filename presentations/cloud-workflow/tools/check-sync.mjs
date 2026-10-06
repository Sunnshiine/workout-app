// Proves the presenter window and the audience window drive each other, step by step, and the stage letterboxes.
// Usage: node tools/check-sync.mjs <harness dir>
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const harness = resolve(process.argv[2]);
const { chromium } = createRequire(`${harness}/package.json`)('playwright-core');
const deck = pathToFileURL(resolve(fileURLToPath(import.meta.url), '../../index.html')).href;
// Where a window is, read from the DOM rather than the hash: the active slide and how many steps it shows.
const where = (p) => p.evaluate(() => {
  const slides = [...document.querySelectorAll('section.slide')];
  const i = slides.findIndex((s) => s.classList.contains('active'));
  const on = Math.max(0, ...[...slides[i].querySelectorAll('[data-step].on')].map((el) => +el.dataset.step));
  return `${i + 1}.${on}`;
});
const failures = [];
const expect = (ok, what) => { console.log(ok ? 'ok  ' : 'FAIL', what); if (!ok) failures.push(what); };
const press = async (from, key, to) => { await from.keyboard.press(key); await to.waitForTimeout(250); };

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const presenter = await ctx.newPage();
await presenter.goto(`${deck}?presenter#1`);
const [audience] = await Promise.all([ctx.waitForEvent('page'), presenter.click('[data-open]')]);
await audience.waitForLoadState();
await audience.waitForTimeout(300);
expect(await where(audience) === '1.0', 'audience opens on the presenter slide');
await press(presenter, 'ArrowRight', audience);
expect(await where(audience) === '2.0', 'presenter ArrowRight moves the audience to slide 2, step 0');
await press(audience, 'Space', presenter);
expect(await where(presenter) === '2.1', 'audience Space moves the presenter to slide 2, step 1');
expect((await presenter.textContent('.count')).replace(/\s+/g, ' ') === 'slide 2 / 18 · step 1 / 2', 'presenter counter shows slide and step');
await press(presenter, 'ArrowRight', audience);
expect(await where(audience) === '2.2', 'presenter ArrowRight reveals step 2 in the audience');
await press(audience, 'ArrowRight', presenter);
expect(await where(presenter) === '3.0', 'audience ArrowRight past the last step moves the presenter to slide 3');
await press(presenter, 'PageUp', audience);
expect(await where(audience) === '2.2', 'clicker PageUp returns both to slide 2, fully revealed');
await press(audience, 'PageUp', presenter);
expect(await where(presenter) === '2.1', 'audience PageUp hides step 2 in the presenter');
expect(await audience.evaluate(() => location.hash) === '#2.1', 'audience hash follows the step');

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

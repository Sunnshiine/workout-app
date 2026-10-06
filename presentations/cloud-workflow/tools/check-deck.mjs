import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [harness, deckPath, outDir = 'out', width = '1920', height = '1080'] = process.argv.slice(2);
if (!harness || !deckPath) {
  console.error('usage: node check-deck.mjs <dir with playwright-core in node_modules> <index.html> [outDir] [width] [height]');
  process.exit(2);
}
const { chromium } = createRequire(resolve(harness) + '/')('playwright-core');
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: +width, height: +height } });
const problems = [];
page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text()}`));
page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()}`));
page.on('response', (r) => r.status() >= 400 && problems.push(`http ${r.status()}: ${r.url()}`));

const url = pathToFileURL(resolve(deckPath)).href;
await page.goto(url);
await page.waitForLoadState('networkidle');

const count = await page.locator('section.slide').count();
const report = [];
for (let i = 0; i < count; i++) {
  if (i > 0) await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(900);
  const state = await page.evaluate((i) => {
    const slide = document.querySelectorAll('section.slide')[i];
    const active = slide.classList.contains('active');
    const imgs = [...slide.querySelectorAll('img')].map((img) => ({
      src: img.getAttribute('src'),
      ok: img.complete && img.naturalWidth > 0,
      alt: img.getAttribute('alt') ?? '',
    }));
    const notes = slide.querySelector('aside.notes')?.textContent.trim() ?? '';
    const words = (slide.innerText || '').replace(notes, '').trim().split(/\s+/).filter(Boolean).length;
    const r = slide.getBoundingClientRect();
    const overflow = [...slide.querySelectorAll('*')].filter((el) => {
      if (el.closest('aside.notes')) return false;
      const b = el.getBoundingClientRect();
      return b.width > 0 && (b.right > r.right + 1 || b.bottom > r.bottom + 1 || b.left < r.left - 1 || b.top < r.top - 1);
    }).map((el) => el.tagName + '.' + el.className).slice(0, 5);
    return { title: slide.dataset.title ?? '', hash: location.hash, active, imgs, notesChars: notes.length, visibleWords: words, overflow };
  }, i);
  const file = `${outDir}/slide-${String(i + 1).padStart(2, '0')}.png`;
  await page.screenshot({ path: file });
  if (!state.active) problems.push(`slide ${i + 1} not active after navigation`);
  for (const img of state.imgs) {
    if (!img.ok) problems.push(`slide ${i + 1} broken image ${img.src}`);
    if (!img.alt) problems.push(`slide ${i + 1} image without alt ${img.src}`);
  }
  if (state.notesChars < 40) problems.push(`slide ${i + 1} has thin or missing speaker notes`);
  if (state.overflow.length) problems.push(`slide ${i + 1} content outside slide bounds: ${state.overflow.join(', ')}`);
  report.push({ n: i + 1, ...state, imgs: state.imgs.length, file });
}

await page.keyboard.press('ArrowLeft');
await page.waitForTimeout(500);
const backOk = await page.evaluate((c) => document.querySelectorAll('section.slide')[c - 2]?.classList.contains('active'), count);
if (count > 1 && !backOk) problems.push('ArrowLeft did not return to the previous slide');

await page.goto(url + '#3');
await page.waitForTimeout(600);
const deepLinkOk = await page.evaluate(() => document.querySelectorAll('section.slide')[2]?.classList.contains('active'));
if (count >= 3 && !deepLinkOk) problems.push('deep link #3 did not open slide 3');

const presenter = await browser.newPage({ viewport: { width: 1440, height: 900 } });
presenter.on('pageerror', (e) => problems.push(`presenter pageerror: ${e.message}`));
await presenter.goto(url + '?presenter#2');
await presenter.waitForTimeout(800);
const presenterNotes = await presenter.evaluate(() => document.querySelector('[data-presenter-notes]')?.textContent.trim().length ?? 0);
await presenter.screenshot({ path: `${outDir}/presenter.png` });
if (presenterNotes < 40) problems.push('presenter view shows no notes');

await browser.close();
console.log(JSON.stringify({ slides: count, report, problems }, null, 2));
process.exit(problems.length ? 1 : 0);

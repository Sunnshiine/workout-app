// Walks the deck one press of next at a time, screenshots every step, and checks each step reveals something.
// Usage: node tools/check-deck.mjs <dir with playwright-core in node_modules> <index.html> [outDir]
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [harness, deckPath, outDir = 'out'] = process.argv.slice(2);
if (!harness || !deckPath) {
  console.error('usage: node check-deck.mjs <dir with playwright-core in node_modules> <index.html> [outDir]');
  process.exit(2);
}
const { chromium } = createRequire(resolve(harness) + '/')('playwright-core');
mkdirSync(`${outDir}/reduced`, { recursive: true });
const url = pathToFileURL(resolve(deckPath)).href;
const pad = (n) => String(n).padStart(2, '0');
const problems = [];

const browser = await chromium.launch({ channel: 'chrome', headless: true });

function watch(page, label) {
  page.on('console', (m) => m.type() === 'error' && problems.push(`${label} console: ${m.text()}`));
  page.on('pageerror', (e) => problems.push(`${label} pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`${label} requestfailed: ${r.url()}`));
  page.on('response', (r) => r.status() >= 400 && problems.push(`${label} http ${r.status()}: ${r.url()}`));
}

async function settle(page) {
  await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== 'running'), null, { timeout: 5000 });
  await page.waitForTimeout(40);
}

// What the slide shows right now: which steps are visible, and whether anything else is off.
const inspect = (page, i) => page.evaluate((i) => {
  const slide = document.querySelectorAll('section.slide')[i];
  const byStep = {};
  for (const el of slide.querySelectorAll('[data-step]')) {
    const k = +el.dataset.step;
    byStep[k] ??= { total: 0, shown: 0, hidden: 0 };
    byStep[k].total++;
    const o = getComputedStyle(el).opacity;
    if (o === '1') byStep[k].shown++;
    if (o === '0') byStep[k].hidden++;
  }
  const notes = slide.querySelector('aside.notes')?.textContent.trim() ?? '';
  const r = slide.getBoundingClientRect();
  const overflow = [...slide.querySelectorAll('*')].filter((el) => {
    if (el.closest('aside.notes')) return false;
    const b = el.getBoundingClientRect();
    return b.width > 0 && (b.right > r.right + 1 || b.bottom > r.bottom + 1 || b.left < r.left - 1 || b.top < r.top - 1);
  }).map((el) => `${el.tagName}.${el.getAttribute('class') ?? ''}`).slice(0, 5);
  return {
    title: slide.dataset.title ?? '',
    active: slide.classList.contains('active'),
    hash: location.hash,
    byStep,
    imgs: [...slide.querySelectorAll('img')].map((img) => ({ src: img.getAttribute('src'), ok: img.complete && img.naturalWidth > 0, alt: img.getAttribute('alt') ?? '' })),
    notesChars: notes.length,
    overflow,
  };
}, i);

function checkStep(state, slideNo, step, label) {
  if (!state.active) problems.push(`${label} slide ${slideNo} not active`);
  const want = step ? `#${slideNo}.${step}` : `#${slideNo}`;
  if (state.hash !== want) problems.push(`${label} slide ${slideNo} step ${step}: hash ${state.hash}, want ${want}`);
  for (const [k, c] of Object.entries(state.byStep)) {
    if (+k <= step && c.shown !== c.total) problems.push(`${label} slide ${slideNo} step ${step}: ${c.total - c.shown} of step ${k}'s ${c.total} items not fully shown`);
    if (+k > step && c.hidden !== c.total) problems.push(`${label} slide ${slideNo} step ${step}: step ${k} shows early`);
  }
  if (step > 0 && !(state.byStep[step]?.shown > 0)) problems.push(`${label} slide ${slideNo} step ${step} reveals nothing`);
}

// Full walk at 1920x1080, every state screenshotted.
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
watch(page, 'deck');
await page.goto(url);
await page.waitForLoadState('networkidle');
const lastSteps = await page.evaluate(() => [...document.querySelectorAll('section.slide')].map((s) => Math.max(0, ...[...s.querySelectorAll('[data-step]')].map((el) => +el.dataset.step))));
const report = [];
let states = 0;
for (let i = 0; i < lastSteps.length; i++) {
  for (let step = 0; step <= lastSteps[i]; step++) {
    if (i > 0 || step > 0) await page.keyboard.press('ArrowRight');
    await settle(page);
    const state = await inspect(page, i);
    checkStep(state, i + 1, step, 'walk');
    await page.screenshot({ path: `${outDir}/slide-${pad(i + 1)}-s${pad(step)}.png` });
    states++;
    if (step < lastSteps[i]) continue;
    await page.screenshot({ path: `${outDir}/slide-${pad(i + 1)}.png` });
    for (const img of state.imgs) {
      if (!img.ok) problems.push(`slide ${i + 1} broken image ${img.src}`);
      if (!img.alt) problems.push(`slide ${i + 1} image without alt ${img.src}`);
    }
    if (state.notesChars < 40) problems.push(`slide ${i + 1} has thin or missing speaker notes`);
    if (state.overflow.length) problems.push(`slide ${i + 1} content outside slide bounds: ${state.overflow.join(', ')}`);
    report.push({ n: i + 1, title: state.title, steps: lastSteps[i], imgs: state.imgs.length });
  }
}
await page.keyboard.press('ArrowRight');
await settle(page);
checkStep(await inspect(page, lastSteps.length - 1), lastSteps.length, lastSteps.at(-1), 'next past the end');

// Back from slide 3 step 0 lands on slide 2 fully revealed, with nothing left animating.
await page.goto(`${url}#3`);
await settle(page);
checkStep(await inspect(page, 2), 3, 0, 'deep link #3');
await page.keyboard.press('ArrowLeft');
checkStep(await inspect(page, 1), 2, lastSteps[1], 'back from 3.0, no wait');
await page.keyboard.press('ArrowLeft');
checkStep(await inspect(page, 1), 2, lastSteps[1] - 1, 'back hides a step instantly');

const deep = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
watch(deep, 'deep link');
await deep.goto(`${url}#7.3`);
await settle(deep);
checkStep(await inspect(deep, 6), 7, 3, 'deep link #7.3');
await deep.screenshot({ path: `${outDir}/deeplink-7.3.png` });

// Presenter: notes, step counter, and Now/Next frames that follow steps.
for (const [w, h, file] of [[1440, 900, 'presenter.png'], [1280, 720, 'presenter-1280.png']]) {
  const p = await browser.newPage({ viewport: { width: w, height: h } });
  watch(p, `presenter ${w}`);
  await p.goto(`${url}?presenter#4.2`);
  await settle(p);
  const ui = await p.evaluate(() => {
    const [now, next] = document.querySelectorAll('.presenter-ui .frame');
    return {
      notes: document.querySelector('[data-presenter-notes]')?.textContent.trim().length ?? 0,
      count: document.querySelector('.presenter-ui .count')?.textContent ?? '',
      nowOn: now.querySelectorAll('[data-step].on').length,
      nowSteps: [...now.querySelectorAll('[data-step].on')].map((el) => +el.dataset.step),
      nextMax: Math.max(0, ...[...next.querySelectorAll('[data-step].on')].map((el) => +el.dataset.step)),
      frameBottom: now.getBoundingClientRect().bottom,
      clockRight: document.querySelector('.presenter-ui .clock').getBoundingClientRect().right,
    };
  });
  await p.screenshot({ path: `${outDir}/${file}` });
  if (ui.notes < 40) problems.push(`presenter ${w}: no notes`);
  if (!/slide 4 \/ \d+\s+·\s+step 2 \/ 5/.test(ui.count)) problems.push(`presenter ${w}: counter reads "${ui.count}"`);
  if (!ui.nowOn || Math.max(...ui.nowSteps) !== 2) problems.push(`presenter ${w}: Now frame is not at step 2`);
  if (ui.nextMax !== 3) problems.push(`presenter ${w}: Next frame is not step 3, got ${ui.nextMax}`);
  if (ui.frameBottom > h) problems.push(`presenter ${w}: Now frame runs off the window`);
  if (ui.clockRight > w) problems.push(`presenter ${w}: the clock runs off the header`);
  await p.close();
}

// Reduced motion: reveals fade without moving, nothing draws, and the close shows its final state at once.
const rctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, reducedMotion: 'reduce' });
const rpage = await rctx.newPage();
watch(rpage, 'reduced');
await rpage.goto(url);
await rpage.waitForLoadState('networkidle');
for (let i = 0; i < lastSteps.length; i++) {
  for (let step = 0; step <= lastSteps[i]; step++) {
    if (i > 0 || step > 0) await rpage.keyboard.press('ArrowRight');
    const moving = await rpage.evaluate(() => document.getAnimations().filter((a) => a.playState === 'running')
      .map((a) => a.transitionProperty ?? a.animationName).filter((p) => p !== 'opacity'));
    if (moving.length) problems.push(`reduced slide ${i + 1} step ${step}: animates ${[...new Set(moving)].join(', ')}`);
    await settle(rpage);
    checkStep(await inspect(rpage, i), i + 1, step, 'reduced');
  }
  await rpage.screenshot({ path: `${outDir}/reduced/slide-${pad(i + 1)}.png` });
}

await browser.close();
console.log(JSON.stringify({ slides: lastSteps.length, states, report, problems }, null, 2));
process.exit(problems.length ? 1 : 0);

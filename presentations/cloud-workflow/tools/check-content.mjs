// Checks the deck's content rules that a screenshot cannot: type sizes, role chips, dashes, notes length.
// Usage: node tools/check-content.mjs <dir holding playwright-core in node_modules>
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const harness = resolve(process.argv[2]);
const { chromium } = createRequire(`${harness}/package.json`)('playwright-core');
const deck = pathToFileURL(resolve(fileURLToPath(import.meta.url), '../../index.html')).href;

const IMAGE_CHIPS = [
  /^APP RENDER( · Active Set Card fixture)? · [0-9a-f]{8}$/,
  /^PROTOTYPE · (browser render|accepted pick)$/,
  /^PRODUCTION · redrawn in HTML$/,
  /^AUDIT RENDER of PR #467 · [0-9a-f]{8}$/,
  /^RECONSTRUCTION · drawn for this talk$/,
  /^TICKET · #\d+$/,
  /^RUN RECORD$/,
];
const QUOTE_CHIPS = [
  /^agent's record( · (PR )?#\d+)?$/,
  /^agent audit · #467$/,
  /^my words · #505$/,
  /^implement prompt · [0-9a-f]{7}$/,
  /^VISUAL_LOOP\.md · [0-9a-f]{8}$/,
  /^[0-9a-f]{8}$/,
];

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto(deck);
await page.waitForLoadState('networkidle');

const slides = await page.evaluate(() => [...document.querySelectorAll('section.slide')].map((slide, i) => {
  slide.classList.add('active');
  const notes = slide.querySelector('aside.notes');
  const tooSmall = [];
  for (const el of slide.querySelectorAll('*')) {
    if (el.closest('aside.notes') || !el.getClientRects().length) continue;
    const ownText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (!ownText) continue;
    const ctm = el instanceof SVGGraphicsElement ? el.getScreenCTM().a / (document.querySelector('.deck').getBoundingClientRect().width / 1920) : 1;
    const px = parseFloat(getComputedStyle(el).fontSize) * ctm;
    const min = el.closest('.chip') ? 14 : 18;
    if (px < min - 0.01) tooSmall.push(`${px.toFixed(1)}px "${el.textContent.trim().slice(0, 30)}"`);
  }
  const visible = (slide.innerText || '').replace(notes?.innerText ?? '', '');
  const alts = [...slide.querySelectorAll('img')].map((img) => img.alt).join(' ');
  return {
    n: i + 1,
    chips: [...slide.querySelectorAll('.chip')].map((c) => c.textContent.replace(/\s+/g, ' ').trim()),
    // An svg marked data-decor holds icons, not a figure, so it needs no role chip.
    hasVisual: !!slide.querySelector('img, svg.art:not([data-decor]), .mini-map'),
    tooSmall,
    visible,
    allText: `${slide.textContent} ${alts}`,
    notes: notes?.innerText.trim() ?? '',
  };
}));
await browser.close();

const problems = [];
for (const s of slides) {
  const words = s.notes.split(/\s+/).filter(Boolean).length;
  if (words < 60 || words > 150) problems.push(`slide ${s.n}: notes have ${words} words, want 60 to 150`);
  if (!/\[[^\]]+\]$/.test(s.notes)) problems.push(`slide ${s.n}: notes do not end with a bracketed source line`);
  if (/[–—]/.test(s.allText)) problems.push(`slide ${s.n}: long dash in text`);
  if (/overnight/i.test(s.visible)) problems.push(`slide ${s.n}: "overnight" on the slide`);
  for (const t of s.tooSmall) problems.push(`slide ${s.n}: text below the size floor: ${t}`);
  const unknown = s.chips.filter((c) => ![...IMAGE_CHIPS, ...QUOTE_CHIPS].some((re) => re.test(c)));
  for (const c of unknown) problems.push(`slide ${s.n}: unknown chip "${c}"`);
  if (s.hasVisual && !s.chips.some((c) => IMAGE_CHIPS.some((re) => re.test(c)))) problems.push(`slide ${s.n}: visual without a role chip`);
}
for (const s of slides) console.log(`slide ${String(s.n).padStart(2)}  notes ${s.notes.split(/\s+/).length} words  chips: ${s.chips.join(' | ')}`);
console.log(problems.length ? `\n${problems.join('\n')}` : '\nno problems');
process.exit(problems.length ? 1 : 0);

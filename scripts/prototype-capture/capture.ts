#!/usr/bin/env -S npx tsx
//
// prototype:capture — screenshot every variant of an HTML prototype at an
// iPhone viewport, ready to embed in a GitHub issue comment. Run `--help` (the
// HELP string below) for usage.
//
// It opens the file over file:// at a current-generation iPhone device
// descriptor, detects the prototype's variant keys and switching convention —
// the `?variant=` search param or a `#a`-style hash, per the `prototype` skill
// (see .agents/skills/prototype/UI.md) — and writes one full-page PNG per
// variant ("<prototype>-<key>.png"), falling back to a single "<prototype>.png"
// when the file has no variants. Scripting multi-state interactions (expanding
// rows, mid-flow states) is out of scope — drive those ad hoc with the same
// `playwright` dependency.
//
// Browser pin (drift note):
//   This relies on the Chromium that Playwright expects being pre-installed in
//   the cloud environment at PLAYWRIGHT_BROWSERS_PATH (/opt/pw-browsers) — no
//   `playwright install`, no download. The `playwright` pin in package.json
//   (~1.56.x) expects Chromium build 1194, which is what the environment ships.
//   If the cloud image bumps its browser, launch fails with
//     "Executable doesn't exist at /opt/pw-browsers/chromium-<build>/…"
//   The fix is to bump the `playwright` pin to the minor whose expected build
//   matches the newly-installed one (check playwright-core's browsers.json), then
//   refresh the lockfile.

import { existsSync, mkdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename, dirname, extname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { chromium, devices } from "playwright";
import {
  detectVariants,
  type VariantConvention,
} from "./detect-variants.js";

// The review surface is an iPhone; one representative current-generation
// viewport is the bar. A session that needs a different device drives Playwright
// ad hoc with the same dependency rather than reaching for a flag here.
const DEVICE = "iPhone 15 Pro";

const HELP = `prototype:capture — screenshot every variant of an HTML prototype at an iPhone viewport ("${DEVICE}").

Usage:
  npm run prototype:capture -- <path-to-html> [--out <dir>]

  <path-to-html>   Local HTML prototype to render (required).
  --out <dir>      Output directory for PNGs. Default: the HTML file's directory.
  --help           Print this help.

Emits one full-page PNG per detected variant ("<prototype>-<key>.png"), or a
single "<prototype>.png" when the prototype has no variants.`;

interface Args {
  htmlPath: string;
  outDir?: string;
}

function parseArgs(argv: string[]): Args {
  let htmlPath: string | undefined;
  let outDir: string | undefined;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--out") {
      outDir = argv[++i];
      if (!outDir) throw new Error("--out needs a directory");
    } else if (arg.startsWith("-")) {
      throw new Error(`Unknown option: ${arg}`);
    } else if (htmlPath === undefined) {
      htmlPath = arg;
    } else {
      throw new Error(`Unexpected extra argument: ${arg}`);
    }
  }

  if (!htmlPath) throw new Error("Missing <path-to-html>. See --help.");
  return { htmlPath: resolve(htmlPath), outDir };
}

/** Build the file:// URL that selects a given variant under a convention. */
function variantUrl(
  fileUrl: string,
  convention: VariantConvention,
  key: string,
): string {
  return convention === "hash"
    ? `${fileUrl}#${key}`
    : `${fileUrl}?variant=${encodeURIComponent(key)}`;
}

/** Filesystem-safe screenshot name derived from the prototype file + key. */
function screenshotName(htmlPath: string, key?: string): string {
  const stem = basename(htmlPath, extname(htmlPath));
  if (!key) return `${stem}.png`;
  const safeKey = key.replace(/[^A-Za-z0-9_-]+/g, "-");
  return `${stem}-${safeKey}.png`;
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(HELP);
    return;
  }
  const { htmlPath, outDir: outArg } = parseArgs(argv);

  if (!existsSync(htmlPath)) {
    throw new Error(`No such file: ${htmlPath}`);
  }
  const outDir = outArg ? resolve(outArg) : dirname(htmlPath);
  mkdirSync(outDir, { recursive: true });

  const descriptor = devices[DEVICE];
  if (!descriptor) {
    throw new Error(
      `Playwright has no "${DEVICE}" device descriptor — the pin may have drifted; pick a current iPhone descriptor.`,
    );
  }

  const html = await readFile(htmlPath, "utf8");
  const { convention, keys } = detectVariants(html);
  const fileUrl = pathToFileURL(htmlPath).href;

  // No variants → one screenshot; otherwise one per variant.
  const shots =
    keys.length === 0
      ? [{ url: fileUrl, name: screenshotName(htmlPath) }]
      : keys.map((key) => ({
          url: variantUrl(fileUrl, convention, key),
          name: screenshotName(htmlPath, key),
        }));

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext(descriptor);
    const page = await context.newPage();
    for (const shot of shots) {
      await page.goto(shot.url, { waitUntil: "networkidle" });
      const out = resolve(outDir, shot.name);
      await page.screenshot({ path: out, fullPage: true });
      console.log(`captured ${shot.name}`);
    }
    await context.close();
  } finally {
    await browser.close();
  }

  const summary =
    keys.length === 0
      ? "no variants detected — captured a single screenshot"
      : `captured ${keys.length} variant(s) via ${convention} convention: ${keys.join(", ")}`;
  console.log(`${summary}\nwrote to ${outDir}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});

// Pure variant detection for the prototype capture script.
//
// A UI prototype (see the `prototype` skill's UI.md) exposes several variants
// on a single HTML file, switchable either via a `?variant=` search param or a
// `#a`-style location hash. This module reads the prototype's HTML source and
// works out which variant keys exist and which switching convention it uses, so
// the capture script can drive one screenshot per variant without launching a
// browser just to discover them.
//
// Detection is deliberately source-level and heuristic: prototypes are
// throwaway code with no shared runtime contract, so we recognise the handful
// of shapes the skill actually produces rather than executing the page.

export type VariantConvention = "query" | "hash";

export interface DetectedVariants {
  /** How the prototype selects a variant: `?variant=` param or `#hash`. */
  convention: VariantConvention;
  /** Variant keys in first-seen order; empty when the file has no variants. */
  keys: string[];
}

/** Collect unique regex capture-group-1 matches in first-seen order. */
function collect(source: string, pattern: RegExp): string[] {
  const seen = new Set<string>();
  for (const match of source.matchAll(pattern)) {
    const key = match[1]?.trim();
    if (key) seen.add(key);
  }
  return [...seen];
}

/** Pull string literals out of an inline array body like `'A', "B", 'C'`. */
function parseKeyList(body: string): string[] {
  return collect(body, /['"]([^'"]+)['"]/g);
}

/**
 * Detect the variant keys and switching convention of a prototype's HTML.
 *
 * Convention: `hash` when the source reads `location.hash` and does not read a
 * `?variant=` search param; otherwise `query` (the skill's default).
 *
 * Keys, in precedence order:
 *   1. An explicit `variants` list (`variants={['A','B','C']}`, `variants: [...]`,
 *      `data-variants="A,B,C"`) — authoritative, preserves declared order.
 *   2. `variant === 'X'` comparisons and `data-variant="X"` attributes.
 *   3. For the hash convention, `href="#x"` anchors.
 *
 * Returns `keys: []` when nothing matches, signalling the caller to fall back to
 * a single screenshot.
 */
export function detectVariants(html: string): DetectedVariants {
  // Base the convention on how the prototype *reads* its selector, not on the
  // mere presence of the word "variant" — a hash prototype often names a
  // variable `variant`, and letting that flip the convention to `query` would
  // render the wrong state. `query` is the skill's default when neither signal
  // (or both) appears.
  const readsHash = /(?:window\.)?location\.hash/.test(html);
  const readsQuery = /URLSearchParams|searchParams|location\.search|[?&]variant=/.test(
    html,
  );
  const convention: VariantConvention =
    readsHash && !readsQuery ? "hash" : "query";

  // 1. Explicit list — either a JS array or a comma-separated data attribute.
  const listMatch = html.match(/variants\s*[:=]\s*\{?\s*\[([^\]]*)\]/);
  if (listMatch) {
    const keys = parseKeyList(listMatch[1]);
    if (keys.length > 0) return { convention, keys };
  }
  const dataListMatch = html.match(/data-variants\s*=\s*['"]([^'"]+)['"]/);
  if (dataListMatch) {
    const keys = dataListMatch[1]
      .split(",")
      .map((k) => k.trim())
      .filter(Boolean);
    if (keys.length > 0) return { convention, keys };
  }

  // 2. Comparison keys and per-element data attributes.
  const keys = [
    ...collect(html, /\bvariant\b\s*===?\s*['"]([^'"]+)['"]/g),
    ...collect(html, /data-variant\s*=\s*['"]([^'"]+)['"]/g),
  ];

  // 3. Hash anchors, only when we're in the hash convention.
  if (convention === "hash") {
    keys.push(...collect(html, /href\s*=\s*['"]#([A-Za-z0-9_-]+)['"]/g));
  }

  return { convention, keys: [...new Set(keys)] };
}

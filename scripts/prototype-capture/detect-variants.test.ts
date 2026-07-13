import { describe, expect, it } from "vitest";
import { detectVariants } from "./detect-variants.js";

describe("detectVariants", () => {
  it("reads an explicit variants array in the switcher (query convention)", () => {
    const html = `
      <script>
        const variant = new URLSearchParams(location.search).get('variant') ?? 'A';
        render(<PrototypeSwitcher variants={['A','B','C']} current={variant} />);
      </script>`;
    expect(detectVariants(html)).toEqual({
      convention: "query",
      keys: ["A", "B", "C"],
    });
  });

  it("infers keys from variant === comparisons when there is no list", () => {
    const html = `
      <script>
        const variant = params.get('variant');
        if (variant === "A") showA();
        else if (variant === 'B') showB();
      </script>`;
    expect(detectVariants(html)).toEqual({
      convention: "query",
      keys: ["A", "B"],
    });
  });

  it("detects the hash convention and its anchor keys", () => {
    const html = `
      <nav>
        <a href="#a">One</a><a href="#b">Two</a><a href="#c">Three</a>
      </nav>
      <script>
        window.addEventListener('hashchange', () => {
          const key = location.hash.slice(1);
        });
      </script>`;
    expect(detectVariants(html)).toEqual({
      convention: "hash",
      keys: ["a", "b", "c"],
    });
  });

  it("stays on the hash convention even when the source mentions 'variant'", () => {
    const html = `
      <a href="#a">A</a><a href="#b">B</a>
      <script>
        // pick the active variant from the hash
        function render() { const variant = location.hash.slice(1) || 'a'; show(variant); }
        window.addEventListener('hashchange', render);
      </script>`;
    expect(detectVariants(html)).toEqual({
      convention: "hash",
      keys: ["a", "b"],
    });
  });

  it("reads a data-variants attribute list", () => {
    const html = `<body data-variants="one, two, three"></body>`;
    expect(detectVariants(html)).toEqual({
      convention: "query",
      keys: ["one", "two", "three"],
    });
  });

  it("deduplicates repeated keys, preserving first-seen order", () => {
    const html = `
      variant === 'B'; variant === 'A'; variant === 'B'; variant === 'A';`;
    expect(detectVariants(html).keys).toEqual(["B", "A"]);
  });

  it("returns no keys for a variant-less file (single-screenshot fallback)", () => {
    const html = `<html><body><h1>Just one layout</h1></body></html>`;
    expect(detectVariants(html)).toEqual({ convention: "query", keys: [] });
  });

  it("prefers the explicit list over scattered comparisons", () => {
    const html = `
      const variants = ['A', 'B'];
      if (variant === 'A') {} else if (variant === 'B') {} else if (variant === 'legacy') {}`;
    expect(detectVariants(html).keys).toEqual(["A", "B"]);
  });
});

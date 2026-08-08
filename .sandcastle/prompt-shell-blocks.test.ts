import * as fs from "node:fs";
import * as path from "node:path";
import { globSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { linkedIssuePromptText, parseLinkedIssueNumber } from "./linked-issue";

// Sandcastle substitutes {{PLACEHOLDER}} args into a template's `!`...``
// shell blocks verbatim and executes each block via `sh -c`, failing the
// whole run on any error. A placeholder inside a shell block is therefore a
// crash waiting for the first empty or sentinel value (#517: a PR with no
// linked issue rendered `gh issue view (none) --comments` — a syntax error
// that killed the run before failure_reason.txt could be written).
//
// Invariant: no placeholder inside any shell block, in any template. The
// allowlist names the audited exceptions whose callers can only ever supply
// a bare number; adding to it requires the same proof about every caller.

// Matches sandcastle's grammar (dist/index.js): SHELL_BLOCK_PATTERN and
// PLACEHOLDER_PATTERN, which tolerates spaces inside the braces.
const SHELL_BLOCK = /!`([^`]+)`/g;
const PLACEHOLDER = /\{\{\s*[A-Za-z_][A-Za-z0-9_]*\s*\}\}/;

const ALWAYS_NUMERIC: Record<string, string[]> = {
  // main.ts always passes String(issue.number) from `gh issue list` JSON.
  "review-prompt.md": ["ISSUE_NUMBER"],
  // PR_NUMBER comes from github.event.pull_request.number on a labeled
  // pull_request_target event and is guarded by required() in update-branch.ts.
  "update-branch/prompt.md": ["PR_NUMBER"],
};

const templates = globSync("**/prompt*.md", { cwd: import.meta.dirname }).filter(
  (p) => !p.includes("node_modules")
);

describe("prompt templates", () => {
  it("finds the templates", () => {
    expect(templates).toContain("review/prompt.md");
    expect(templates).toContain("implement-pr/prompt.md");
  });

  it.each(templates)("%s has no placeholders inside shell blocks", (file) => {
    const text = fs.readFileSync(path.join(import.meta.dirname, file), "utf8");
    const allowed = ALWAYS_NUMERIC[file] ?? [];
    for (const [, command] of text.matchAll(SHELL_BLOCK)) {
      const stripped = allowed.reduce(
        (cmd, name) => cmd.replaceAll(`{{${name}}}`, "0"),
        command
      );
      expect(stripped, `shell block in ${file}: ${command}`).not.toMatch(PLACEHOLDER);
    }
  });
});

describe("parseLinkedIssueNumber", () => {
  it("finds a closes reference", () => {
    expect(parseLinkedIssueNumber("Fixes #123 by doing X")).toBe("123");
  });

  it("returns empty for a bare issue mention without a closing keyword", () => {
    // PR #517's body mentioned "(#505 carried the wiring over unchanged)"
    // but linked no issue — the case that produced the "(none)" sentinel.
    expect(parseLinkedIssueNumber("(#505 carried the wiring over unchanged)")).toBe("");
    expect(parseLinkedIssueNumber(null)).toBe("");
  });
});

describe("linkedIssuePromptText", () => {
  it("says so when there is no linked issue", () => {
    expect(linkedIssuePromptText("", "")).toBe("(no linked issue)");
  });

  it("passes fetched issue content through", () => {
    expect(linkedIssuePromptText("123", "issue body")).toBe("issue body");
  });

  it("keeps a fetch failure distinguishable from no linked issue", () => {
    const text = linkedIssuePromptText("123", "");
    expect(text).toContain("#123");
    expect(text).toContain("gh issue view 123");
    expect(text).not.toBe("(no linked issue)");
  });
});

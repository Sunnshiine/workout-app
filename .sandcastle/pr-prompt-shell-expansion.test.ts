import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import { describe, expect, it } from "vitest";
import { parseLinkedIssueNumber, prPromptArgs } from "./pr-prompt-args";

// Mirrors sandcastle's PromptPreprocessor: every `!`...`` block in the
// substituted prompt is executed via `sh -c`, and a nonzero exit fails the
// whole run. These tests render the real PR-scoped templates with the exact
// args the scripts produce and syntax-check every shell block, so a template
// change can't reintroduce the #517 failure (`gh issue view (none)` — a
// sentinel for "no linked issue" spliced into a shell command).

const templates = ["review", "implement-pr"].map((dir) => ({
  dir,
  text: fs.readFileSync(path.join(import.meta.dirname, dir, "prompt.md"), "utf8"),
}));

function substitute(template: string, args: Record<string, string>): string {
  return template.replace(/\{\{([A-Z0-9_]+)\}\}/g, (match, key) => {
    expect(args, `template references {{${key}}} with no matching arg`).toHaveProperty(key);
    return args[key];
  });
}

function shellBlocks(prompt: string): string[] {
  return [...prompt.matchAll(/!`([^`]+)`/g)].map((m) => m[1]);
}

function bashSyntaxError(command: string): string | null {
  try {
    execFileSync("bash", ["-n", "-c", command], { stdio: ["ignore", "pipe", "pipe"] });
    return null;
  } catch (error) {
    return String((error as { stderr?: unknown }).stderr ?? error);
  }
}

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

describe.each(templates)("$dir prompt shell expansion", ({ text }) => {
  it("renders valid shell blocks for a PR with no linked issue", () => {
    const prompt = substitute(
      text,
      prPromptArgs({
        prNumber: "517",
        branch: "claude/workout-logging-keyboard-wj7ke6",
        issueNumber: "",
        issueTitle: "",
        linkedIssue: "",
        prCommentsJson: "{}",
      })
    );
    for (const command of shellBlocks(prompt)) {
      expect(command).not.toMatch(/\{\{/);
      expect(bashSyntaxError(command), `shell block: ${command}`).toBeNull();
    }
  });

  it("renders valid shell blocks for a PR with a linked issue", () => {
    const prompt = substitute(
      text,
      prPromptArgs({
        prNumber: "517",
        branch: "claude/workout-logging-keyboard-wj7ke6",
        issueNumber: "123",
        issueTitle: "Some issue",
        linkedIssue: "issue body here",
        prCommentsJson: "{}",
      })
    );
    for (const command of shellBlocks(prompt)) {
      expect(command).not.toMatch(/\{\{/);
      expect(bashSyntaxError(command), `shell block: ${command}`).toBeNull();
    }
  });
});

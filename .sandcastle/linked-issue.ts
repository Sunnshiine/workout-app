/**
 * The linked issue of a PR, for substitution into prompt templates.
 *
 * Values substituted into a prompt land inside `!`...`` shell expressions
 * verbatim, and sandcastle fails the whole run if any expression errors — so
 * a PR without a linked issue must never route a sentinel like "(none)" into
 * a shell command (#517: `gh issue view (none) --comments` is a bash syntax
 * error). The issue content is fetched script-side and substituted as plain
 * text instead; prompt-shell-blocks.test.ts enforces the invariant.
 */

/**
 * The `closes/fixes/resolves #N` reference in a PR body, or "" if absent.
 * Same-repo `#N` references only: a cross-repo `owner/repo#N` or URL
 * reference would resolve `gh issue view N` against the wrong repository.
 */
export function parseLinkedIssueNumber(body: string | null | undefined): string {
  return body?.match(/(?:closes|fixes|resolves)\s+#(\d+)/i)?.[1] ?? "";
}

/**
 * The <linked-issue> prompt text. A fetch failure must stay distinguishable
 * from "no linked issue": the agent would otherwise spec-review against
 * nothing while the prompt still names an issue. On failure the agent is
 * told to fetch it itself.
 */
export function linkedIssuePromptText(issueNumber: string, fetched: string): string {
  if (!issueNumber) return "(no linked issue)";
  return (
    fetched ||
    `Fetching issue #${issueNumber} failed — run \`gh issue view ${issueNumber} --comments\` to read it before reviewing.`
  );
}

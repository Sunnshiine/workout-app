/**
 * Prompt arguments shared by the PR-scoped agents (review, implement-pr).
 *
 * Values substituted into a prompt template land inside `!`...`` shell
 * expressions verbatim, and sandcastle fails the whole run if any expression
 * errors. A PR without a `closes/fixes/resolves #N` reference therefore must
 * not route a sentinel like "(none)" into a shell command (#517 failure:
 * `gh issue view (none) --comments` is a bash syntax error). The linked-issue
 * content is fetched script-side and passed as plain text instead.
 */
export function prPromptArgs(input: {
  prNumber: string;
  branch: string;
  issueNumber: string;
  issueTitle: string;
  linkedIssue: string;
  prCommentsJson: string;
}): Record<string, string> {
  return {
    PR_NUMBER: input.prNumber,
    BRANCH: input.branch,
    ISSUE_NUMBER: input.issueNumber || "(none)",
    ISSUE_TITLE: input.issueTitle || "(no linked issue)",
    LINKED_ISSUE: input.linkedIssue || "(no linked issue)",
    PR_COMMENTS_JSON: input.prCommentsJson,
  };
}

/** The `closes/fixes/resolves #N` reference in a PR body, or "" if absent. */
export function parseLinkedIssueNumber(body: string | null | undefined): string {
  return body?.match(/(?:closes|fixes|resolves)\s+#(\d+)/i)?.[1] ?? "";
}

import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { writeFileSync } from "node:fs";
import * as path from "node:path";

const PRD_NUMBER = required("PRD_NUMBER");
const PRD_TITLE = required("PRD_TITLE");
const SUB_ISSUE_NUMBER = required("SUB_ISSUE_NUMBER");
const SUB_ISSUE_TITLE = required("SUB_ISSUE_TITLE");
const BRANCH = required("BRANCH");
const OUTPUT_DIR = required("OUTPUT_DIR");

const result = await sandcastle.run({
  name: `implement-prd-#${PRD_NUMBER}-sub-#${SUB_ISSUE_NUMBER}`,
  agent: sandcastle.claudeCode("claude-opus-4-8", {
    env: {
      CLAUDE_CODE_OAUTH_TOKEN: required("CLAUDE_CODE_OAUTH_TOKEN"),
      // Never background a command (auto-backgrounding included): an agent
      // that ends its session "waiting" on a background build is never
      // resumed past the iteration cap, and its uncommitted work dies with
      // the runner (#497).
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1",
      // Foreground xcodebuild runs must fit inside the Bash ceiling now
      // that nothing backgrounds them. BASH_MAX_TIMEOUT_MS only raises the
      // ceiling the model may request; BASH_DEFAULT_TIMEOUT_MS covers calls
      // that pass no explicit timeout — without it those die at the
      // 2-minute default, killed rather than backgrounded (#497).
      BASH_DEFAULT_TIMEOUT_MS: "1800000",
      BASH_MAX_TIMEOUT_MS: "1800000",
    },
  }),
  sandbox: noSandbox(),
  logging: { type: "stdout" },
  // A silent foreground build must outlive the idle timeout (default 600s),
  // so this stays above BASH_MAX_TIMEOUT_MS.
  idleTimeoutSeconds: 2700,
  // prompt.md tells the agent to end with the completion signal once the
  // sub-issue is committed. The extra iterations resume an agent that ended
  // its turn mid-work — both #497 failures died exactly there, at the old
  // cap of 1 — instead of abandoning the session.
  maxIterations: 3,
  promptFile: path.join(import.meta.dirname, "prompt.md"),
  promptArgs: {
    PRD_NUMBER,
    PRD_TITLE,
    SUB_ISSUE_NUMBER,
    SUB_ISSUE_TITLE,
    BRANCH,
  },
});

// A run that never emitted the completion signal did not finish. Fail loudly
// so the workflow's success()-gated steps (close sub-issue, open PR) never
// run against a half-done session: both #497 failures closed sub-issue #486
// off 0-commit runs precisely because this script exited 0 regardless. A
// re-run whose work already landed in an earlier session still finishes by
// emitting the signal, so zero new commits alone is not failure.
if (!result.completionSignal) {
  const reason =
    `implement agent for sub-issue #${SUB_ISSUE_NUMBER} ended after ` +
    `${result.iterations.length} iteration(s) without emitting the ` +
    `completion signal (commits this run: ${result.commits.length}). ` +
    `The session died mid-work — see the agent log in this workflow run.`;
  writeFileSync(path.join(OUTPUT_DIR, "failure_reason.txt"), reason);
  console.error(`\n${reason}`);
  process.exit(1);
}

console.log(`\nImplementation finished for sub-issue #${SUB_ISSUE_NUMBER}.`);
console.log(`  commits this run: ${result.commits.length}`);

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return value;
}

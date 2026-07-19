// Throwaway spike runner for wayfinder ticket #472 — deleted once the verdict
// is recorded on the ticket. Reproduces the exact sandcastle invocation path
// the agent pipeline uses (claudeCode + noSandbox, --dangerously-skip-permissions,
// prompt over stdin) so the run proves what *that* path can see, not what a
// hand-rolled `claude --mcp-config` call can.
import * as path from "node:path";
import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";

const PROMPT_FILE = required("PROMPT_FILE");

await sandcastle.run({
  name: `spike-472-${path.basename(PROMPT_FILE, ".md")}`,
  agent: sandcastle.claudeCode("claude-opus-4-8", {
    env: {
      CLAUDE_CODE_OAUTH_TOKEN: required("CLAUDE_CODE_OAUTH_TOKEN"),
    },
  }),
  sandbox: noSandbox(),
  logging: { type: "stdout" },
  promptFile: path.join(import.meta.dirname, PROMPT_FILE),
});

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return value;
}

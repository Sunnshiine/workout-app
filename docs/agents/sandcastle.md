# Sandcastle agent pipeline

Label-driven autonomous development on GitHub Actions, ported from
[mattpocock/course-video-manager](https://github.com/mattpocock/course-video-manager).
You write PRDs and issues; Claude Code agents (orchestrated by
[`@ai-hero/sandcastle`](https://github.com/mattpocock/sandcastle)) slice, implement,
review, and open PRs. Prompts and runner scripts live in `.sandcastle/`; the
workflows in `.github/workflows/agent-*.yml` wire them to labels.

## One-time setup

1. **Secrets** (`Settings → Secrets and variables → Actions`):
   - `CLAUDE_CODE_OAUTH_TOKEN` (required) — generate with `claude setup-token`.
     Authenticates the Claude Code runs inside the workflows.
   - `AGENT_PAT` (recommended) — a PAT with `contents`, `issues`, `pull requests`
     (read/write) and `workflows` scope on this repo. Two things break without it:
     labels added by one workflow do not trigger the next (GitHub suppresses
     `GITHUB_TOKEN`-driven events, so the PRD chain and auto-review handoff stall
     and need manual re-labeling), and agent commits touching
     `.github/workflows/` are rejected on push.
2. **Labels** — run the `Agent Setup Labels` workflow once from the Actions tab
   (idempotent; creates every `agent:*` label below).
3. Node tooling is vendored via `package.json` / `package-lock.json`; workflows
   run `npm install` themselves. Nothing to install locally unless you want the
   local loop (below).

## The label vocabulary

Trigger labels (you apply):

| Label | On | What happens |
| --- | --- | --- |
| `agent:to-issues` | a PRD issue | Agent breaks the PRD into ordered, flat, native sub-issues (tracer-bullet vertical slices). |
| `agent:implement` | an issue without sub-issues | Agent implements it on `agent/issue-N-slug`, runs `swift test`, opens a draft PR, then chains into `agent:review`. |
| `agent:implement` | a PRD (issue **with** sub-issues) | Agent implements the first open sub-issue on a shared `agent/prd-N-slug` branch, closes it, re-labels the PRD to pick up the next one, and opens/reuses one draft PR for the whole PRD. When the last sub-issue closes it hands off to `agent:review`. |
| `agent:implement` | a PR | Agent reads unresolved threads/comments, makes the changes, replies in-thread. |
| `agent:review` | a PR | Agent reviews the diff (via the `code-review` skill) against the linked issue and `.sandcastle/CODING_STANDARDS.md`, commits improvements, posts inline comments, marks the PR ready for review, and applies the `testflight` label for a device build (skipped for diffs that can't affect the binary). |
| `agent:update-branch` | a PR | Merges `main` into the branch; an agent resolves conflicts and explains its resolutions in a comment. |
| `agent:queued` | an issue | Parked until its GitHub issue dependencies ("blocked by") close, then auto-promoted to `agent:implement`. |

State labels (workflow-managed — don't apply by hand): `agent:in-progress`,
`agent:blocked` (run failed or refused; read the comment, fix the cause,
re-add the trigger label to retry).

`source:architecture-review` marks PRDs proposed by the scheduled
architecture-review workflow (weekdays 09:00 UTC; skips itself while 10+ such
issues are open).

## The typical loop

1. Write a PRD as a GitHub issue (problem, proposal, non-goals, risks).
2. Label it `agent:to-issues`; review/edit the sub-issues it creates.
3. Label the PRD `agent:implement` and walk away — the chain implements each
   sub-issue, opens one draft PR, and finishes with an agent review.
4. Comment on the PR like you would with any teammate, then label it
   `agent:implement` to have the agent address your feedback, or
   `agent:update-branch` when it conflicts with `main`.
5. Merge. Small standalone issues skip step 1–2: label them
   `agent:implement` directly.

## Repo-specific adaptations

- **macOS runners with Xcode 27.** The reference repo runs everything on
  `ubuntu-latest`; here the implementing/reviewing jobs run on `xcode-27`
  (default Xcode 27.0) so agents can verify the **whole** app, not just the
  SPM library: `swift test` is the fast loop, and changes touching the app
  target (`Views/`, Liquid Glass APIs) are compile-checked with
  `xcodebuild build … -destination 'generic/platform=iOS Simulator'`.
  Workflows pre-create `Secrets.xcconfig` from
  `Secrets.xcconfig.template` (build-only placeholder values; the xcodeproj
  references the file, so builds fail without it). Read-only jobs
  (`to-issues`, `promote-queued`, `architecture-review`) stay on Ubuntu.
  macOS minutes are free while this repo is public; 10× metered if it goes
  private.
- **CI gate.** `ci.yml` runs `swift test`, the app-target compile-check, and
  the ADR-0007 Visual Regression gate (`visual-tests`: the pinned-simulator
  snapshot suite with recording off, so a missing or drifted Visual Baseline
  fails the PR) on every PR. Agent pushes trigger it only when `AGENT_PAT` is
  configured (plain-`GITHUB_TOKEN` pushes don't fire workflows).
- **The sighted loop.** Implementing agents don't just compile UI changes —
  they look at them (`.sandcastle/VISUAL_LOOP.md`, decided on map #468): a
  UI-touching change records its Visual Baselines on the runner's simulator
  and reads the PNGs against `docs/design/greenhouse-picks/`, and drives the
  built app in fixture mode through the changed screens via the XcodeBuildMCP
  tools (`.mcp.json`; headless — the simulator boots windowless via `simctl`),
  screenshotting both appearances. The review agent reads recorded baselines
  and gate diff artifacts against the same ground truth. The deterministic
  `visual-tests` gate stays the sole pass/fail authority. `WorkoutTrackerUITests`
  (XCUITest) remain off-limits in the agent loop — the sighted loop replaces
  the screenshot-tour idea, which was rejected (#469).
- **Commit prefixes.** CI agents use conventional commits. The local loop
  uses `SANDCASTLE:` — never `RALPH:`, which is reserved for the Ralph loop.
- **Agent model** is set in the `.sandcastle/**/*.ts` scripts
  (`sandcastle.claudeCode("claude-opus-4-8")`).

## Local loop (optional)

`npm run sandcastle` runs `.sandcastle/main.ts`: plan → parallel implement →
review → merge, in Docker sandboxes built from `.sandcastle/Dockerfile`
(needs `.sandcastle/.env`, see `.env.example`). Caveat: the sandbox is Linux,
so agents there cannot run `swift test` — prefer the GitHub Actions flow for
anything where the test feedback loop matters.

`npm run test:sandcastle` / `npm run typecheck:sandcastle` cover the pipeline's
own TypeScript.

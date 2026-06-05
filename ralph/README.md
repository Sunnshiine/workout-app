# Ralph — autonomous issue-remediation loop

Ralph runs an AI coding agent (Claude Code **or** Codex) in a loop. Each iteration picks one
GitHub issue labelled `ready-for-agent`, fixes it end-to-end in an isolated git worktree, gates
the result on the full documented testing framework, then ships to the issue's resolved target and
closes the issue. Normal issues still merge to `main`; issues with a `Target branch` directive
push back to that existing PR branch instead. It stops when no eligible issues remain.

It is the issue-driven adaptation of the [Ralph Wiggum loop](https://github.com/coleam00/ralph-loop-quickstart):
GitHub issues replace the quickstart's `prd.md`, and every iteration runs in a **fresh agent
context** so the work never accumulates context bloat.

> ⚠️ **By default Ralph is fully autonomous: it pushes to the resolved target and closes issues
> without asking.** Read [Safety](#safety) before your first un-gated run. Use `--no-push` while
> you build trust.

---

## Prerequisites

- **An agent CLI**, at least one of:
  - Claude Code (`claude`) — default engine.
  - Codex (`codex`) — `--engine codex`.
- **`gh`** authenticated against this repo (`gh auth status`). Used to list/close issues and post comments.
- **`xcodegen`** (`brew install xcodegen`) — new Swift files must be added to the project before `xcodebuild` sees them.
- **Xcode 26+** and the **iPhone 17 Pro** simulator runtime (see `../docs/TESTING.md`).
- **`Secrets.xcconfig`** for Xcode gates in worktrees. Ralph copies it
  automatically from `SECRETS_XCCONFIG_SOURCE` or the repo root when a source
  exists.
- Run from anywhere inside the repo; the script locates the repo root itself.

---

## Quick start

```bash
# Safest first run: one issue, keep commits local.
ralph/ralph.sh --engine claude --max-iterations 1 --no-push

# Full autonomous run with Claude (auto-detects main vs existing PR branch, closes issues):
ralph/ralph.sh

# Same, driven by Codex:
ralph/ralph.sh --engine codex

# Force a PR-branch queue, useful when every selected issue belongs to the same existing PR:
ralph/ralph.sh --publish-target branch --target-branch codex/live-activity-rest-sets-left --target-pr 177

# See the inline help:
ralph/ralph.sh --help
```

A good first target is a **pure-logic issue** (no UI), so the run finishes fast and skips the
screenshot gate.

### Python live GitHub dry-run

The side-by-side Python runner has one controlled live dry-run path for the replacement gate. It
uses only the fake engine, so it cannot invoke Codex, Claude, or any autonomous code-editing agent.
It still mutates GitHub state on a deliberately marked control issue so reviewers can inspect
authenticated label, PR, comment, branch, draft, and ready-state wiring before `ralph.sh` is
replaced.

Create a temporary control issue with both safeguards:

- title starts with `[Ralph dry-run]`
- body contains the exact line `Ralph live dry-run: authorized`

Then run:

```bash
uv run --python 3.11 python -m ralph.orchestrator \
  --repo Sunnshiine/workout-app \
  --live-github-dry-run <control-issue-number>
```

The command always forces `--engine fake`, creates or reuses branch
`ralph/dry-run/issue-<control-issue-number>`, pushes only
`docs/ralph/live-dry-runs/issue-<control-issue-number>.md`, creates or reuses a PR, marks the PR
ready, applies `agent-implemented` to the control issue, applies `agent-ready-for-review` to the PR,
and posts an issue comment. The evidence file is also written into the invoking worktree for the
final replacement review. Delete the `ralph/dry-run/issue-*` branch and close the control PR/issue
after review.

---

## How it works

Each iteration:

```
1. SELECT   An agent lists open `ready-for-agent` issues, skips PRDs/epics, respects
            dependencies, and picks ONE highest-priority unblocked issue.   (read-only)
2. TARGET   Ralph resolves the publication target. Default `auto` mode uses main unless the issue
            has a `Target branch` directive, or the operator passed `--target-branch`.
3. ISOLATE  A fresh worktree + branch `agent/issue-<N>` is created off the resolved target.
4. IMPLEMENT A fresh TDD agent reads the issue contract, implements the issue, runs non-UI
            checks, commits, and emits the exact phase promise.
5. SWIFT    A fresh review agent invokes `swift-reviewer`, remediates blocking findings,
            commits fixes, and emits the exact phase promise.
6. UI       A fresh UI verification agent owns UI integration tests, screenshots, and
            `ui-screenshot-reviewer`; if it changes production Swift/project files, Ralph
            runs SWIFT again before accepting the issue.
7. GATE     The loop independently runs `swift test`, Xcode unit/component tests,
            Visual Regression tests when Views/Theme changed, Xcode UI integration tests,
            and `swiftlint lint --quiet`.
8. UI GATE  If the change touched Views/Theme, the loop confirms the UI phase produced a
            reviewed screenshot artifact. The loop also enforces the Visual Baseline
            authority policy for added, modified, and deleted baseline PNGs.
9. SHIP     Merge the issue branch into the resolved target. Main-target issues fast-forward
            local main and push origin/main. Branch-target issues push the gated merge commit to
            origin/<target-branch>, leave the PR open, and close only the child issue.
10. CLEANUP Remove the worktree and delete the branch.
```

If any step fails, the issue is relabelled **`ready-for-human`** with an explanatory comment, and
the loop moves on to the next issue (it won't get stuck retrying the same one).

The loop stops when the selector returns `SELECTED_ISSUE=NONE` or after `--max-iterations`.

---

## Options

| Flag | Env var | Default | Meaning |
|------|---------|---------|---------|
| `--engine claude\|codex` | `ENGINE` | `claude` | Which agent CLI drives the loop. |
| `--max-iterations N` | `MAX_ITER` | `5` | Max issues to process this run. |
| `--no-push` | `PUSH=0` | push on | Keep successful work local; main-target issues merge to local `main`, branch-target issues leave the gated integration worktree in place. |
| `--model NAME` | `MODEL` | `opus` (claude) | Model alias passed to the engine. |
| `--device "..."` | `SIM_DEVICE` | `iPhone 17 Pro` | Simulator for the build + screenshot. |
| `--codex-sandbox` | `CODEX_BYPASS=0` | bypass on | Run Codex in `workspace-write` sandbox instead of full-access unattended mode. This is safer, but Xcode builds and simulator access may fail. |
| `--publish-target auto\|main\|branch` | `PUBLISH_TARGET` | `auto` | `auto` ships to main unless the issue has a target branch directive; `main` forces direct-to-main; `branch` forces an existing PR branch. |
| `--target-branch BRANCH` | `TARGET_BRANCH` | issue directive | Existing PR branch to use when `--publish-target branch`, or to override issue body detection in `auto`. |
| `--target-pr N` | `TARGET_PR` | detected from issue body | Optional PR number used only in closeout text. Ralph never merges or closes this PR. |
| — | `LABEL` | `ready-for-agent` | The label that marks an issue as AFK-ready. |
| — | `HUMAN_LABEL` | `ready-for-human` | Label applied when the loop gives up on an issue. |

Env vars and flags can be combined, e.g. `MAX_ITER=3 ralph/ralph.sh --engine codex --no-push`.

---

## What makes an issue eligible

The selector picks an issue only if it:

- is **open** and labelled **`ready-for-agent`**,
- is **not** a `PRD:`-titled umbrella spec or a parent/epic tracking issue,
- is **not** also labelled `ready-for-human`,
- has **no unfinished dependency** (a foundational module must close before its consumers run).

Write issues with a clear implementation contract: either an **Agent Brief** comment or a concrete
issue body with acceptance criteria, key interfaces, and out-of-scope notes. When an Agent Brief
comment exists, it wins. When it does not, the issue body may be used as the contract if it is
specific enough to implement directly. The richer the acceptance criteria, the more reliably the
loop succeeds and the more the UI screenshot review can verify.

PRDs are intentionally excluded. Ralph should not select `PRD:` issues or use PRD documents as
implementation input; the issue contract must come from a non-PRD work issue.

### Existing PR Branch Queues

Use a Branch Directive when an issue should build on and push back to an existing PR instead of
shipping directly to `main`:

```markdown
## Agent Brief / Branch Directive

This issue is part of PR #177:
https://github.com/Sunnshiine/workout-app/pull/177

Target branch:
`codex/live-activity-rest-sets-left`

Work from and push back to the PR branch. Do not push `origin/main`, do not merge to `main`,
do not open a new PR, and do not merge or close PR #177. Close this issue only after the PR branch
push succeeds.
```

In default `auto` mode Ralph detects the `Target branch` value, creates the implementation and
integration worktrees from that branch, pushes the gated merge commit to `origin/<target-branch>`,
and leaves the PR open. For a whole queue with the same target, operators can pass
`--publish-target branch --target-branch <branch>` instead of repeating the directive.

Operator recipe for the Live Activity queue:

```bash
ralph/ralph.sh --publish-target branch --target-branch codex/live-activity-rest-sets-left --target-pr 177
```

That command makes every selected child issue start from and push back to
`origin/codex/live-activity-rest-sets-left`. It must not push `origin/main`, merge to `main`, open
a replacement PR, or merge or close PR #177. Ralph closes only the child issue after the PR branch
push succeeds.

---

## Phase-Owned Review

Each mutating phase is a separate fresh agent context and must end with its exact
phase-specific promise line, for example `<promise phase="swift-review">COMPLETE</promise>`.
Generic wording such as "done" or the old `<promise>COMPLETE</promise>` marker does not advance
the loop.

- The TDD implementation phase must not run UI integration tests, screenshots, `swift-reviewer`,
  or `ui-screenshot-reviewer`.
- The Swift review phase must invoke the configured `swift-reviewer` custom agent as a separate
  subagent, so review comes from a fresh context rather than self-review. It must not run UI
  integration tests or screenshot review.
- The UI verification phase must own Xcode UI integration tests. For `WorkoutTracker/Views/` or
  `WorkoutTracker/Theme.swift` changes, it must capture a UITEST fixture screenshot with
  `ralph/snapshot.sh` and invoke the configured `ui-screenshot-reviewer` custom agent as a separate
  subagent.
- If Visual Baselines under `Tests/Visual/__Snapshots__` are modified, the UI verification phase
  must create an old/new/diff image bundle and invoke `ui-screenshot-reviewer` in baseline-diff mode.
  The reviewer answers whether every changed pixel is explained by the issue acceptance criteria.
  Added baselines need no baseline-diff review; deleted baselines must block for a human.
- If the UI verification phase changes production Swift or project files, Ralph runs a fresh
  `swift-review-after-ui` phase before integration.
- Codex CLI supports subagent workflows and custom agents; Ralph expects Codex to spawn the
  configured review agents rather than falling back to copied reviewer instructions.
- Blocking reviewer findings are not final loop failures. The owning phase fixes them in the same
  worktree, reruns required checks or screenshot capture, commits any changes, and requests review
  again before completing.
- If the implementer cannot invoke a required review subagent, it must report BLOCKED instead of
  emitting its phase-specific COMPLETE promise.

Ralph does not currently set Codex subagent depth. If Codex refuses to spawn a reviewer due to depth
limits, configure Codex `[agents] max_depth` high enough for phase-owned review subagents.

---

## The UITEST fixture (UI verification)

`swift test` can't exercise SwiftUI views, and a normal launch hits the Google sign-in wall — so
the app supports a `-UITEST_FIXTURE` launch argument (DEBUG only) that boots straight into a
populated `SessionView` using in-memory seeded data and a faked sign-in. No network, no auth, no
real data touched.

`snapshot.sh` launches with `-UITEST_FIXTURE -UITEST_SESSION` by default to produce
a seeded SessionView verification screenshot:

```bash
# Screenshot the current working tree:
ralph/snapshot.sh                       # writes ralph/.artifacts/screenshot.png

# Screenshot a specific checkout/worktree, to a chosen path:
PROJECT_DIR=/path/to/worktree ralph/snapshot.sh /tmp/out.png

# Screenshot a different fixture route:
UITEST_ARGS="-UITEST_DEVELOPER_TOOLS" ralph/snapshot.sh /tmp/tools.png
```

The UI screenshot review only judges what a **static image** can show (layout, missing/clipped
elements, blank screens). It deliberately does **not** fail issues for animations or interaction —
those ride on the build/test gate and Swift review.

## Visual Regression gate and baseline authority

Ralph keeps the screenshot review and the Visual Regression gate as separate checks. The screenshot
review catches obvious static rendering failures in one fixture route. The Visual Regression gate
compares hosted SwiftUI renders against committed Visual Baselines under
`Tests/Visual/__Snapshots__`.

During the final gate, Ralph runs `WorkoutTrackerSnapshotTests` only when the issue changed
`WorkoutTracker/Views/` or `WorkoutTracker/Theme.swift`. Visual tests run with recording disabled,
so a pixel drift fails instead of silently updating a baseline. The normal autonomous fix path is to
change code until the Visual diff returns to zero.

Ralph also checks baseline file changes with `git diff --name-status HEAD -- Tests/Visual/__Snapshots__`
on the integrated tree:

- `A` added baseline: allowed. This represents a net-new screen or Visual test; the normal UI
  reviewer still judges the new UI surface where applicable.
- `M` modified baseline: allowed only when the UI phase saved a matching baseline-diff review under
  `ralph/.artifacts/visual-baseline-reviews/` and the final line is exactly
  `PASS: no blocking static visual findings.`
- `D` deleted baseline: blocked and flagged for human review.
- Any other status, including rename/copy, is blocked and flagged for human review.

The baseline-diff bundle contains the old baseline from `ISSUE_BASE_REF`, the new baseline from the
issue worktree, and a generated old/new/diff PNG from `ralph/visual-baseline-diff.swift`. The
`ui-screenshot-reviewer` reviews that bundle against the issue acceptance criteria and answers
whether every changed pixel is explained by the issue.

---

## Output & logs

Everything runtime lands under `ralph/.artifacts/` (gitignored):

- `activity.md` — human-readable timeline of every run (selections, outcomes, failures).
- `observations.md` — append-only, read-only signal harvested from each iteration: doc
  gaps, friction, and possible recurrences the implementer flagged, plus loop-written
  `GATE-FAIL` entries. Never auto-applied to docs — review it periodically and consolidate
  manually when an entry flags the file as large (see below).
- `logs/iter-<n>-*.log` — raw agent output and gate logs per phase, per iteration.
- `iter-<n>-issue-<m>.png` — the verification screenshot for View-touching issues.

Each IMPLEMENT agent emits a `<observations>…</observations>` block (or `NONE`) before its
completion promise; the loop appends it under a `## <ts> · iter N · #issue · OUTCOME` header.
The agent reads only the tail of `observations.md` to flag repeats and trips a one-line
"large, consider consolidation" note past a line threshold — it never rewrites the file.

Start here when an issue gets flagged `ready-for-human` — the comment on the issue says *why*,
and the matching log has the detail.

Gate failures are reported by layer:

- Package unit/component tests: `swift test`.
- Xcode unit/component tests: `WorkoutTrackerTests`.
- Visual Regression tests: `WorkoutTrackerSnapshotTests` when Views/Theme changed.
- UI integration tests: `WorkoutTrackerUITests`.
- Lint: `swiftlint lint --quiet`.
- Visual Baseline authority policy: added baselines allowed, modified baselines require a saved
  PASS review, deleted baselines block.
- UI screenshot artifact check: only when `WorkoutTracker/Views/` or `WorkoutTracker/Theme.swift`
  changed. The screenshot review itself happens inside the UI verification phase via the
  `ui-screenshot-reviewer` subagent.

### Execution report

Use the read-only report script when you want per-issue Ralph telemetry from the local artifacts
and Codex sessions:

```bash
uv run --python 3.11 python ralph/report.py
uv run --python 3.11 python ralph/report.py --issue 157 --format json
uv run --python 3.11 python ralph/report.py --format csv
```

The report derives issue attempts and durations from `ralph/.artifacts/activity.md`, attaches
matching phase/gate logs from `ralph/.artifacts/logs/`, and joins Codex token telemetry from
`~/.codex/sessions`. It reports total/cached/uncached tokens, output and reasoning tokens,
compaction counts and timestamps, session/subagent counts, reviewer roles, per-phase token totals,
max per-call context size, and tokens per minute. GitHub and git are not touched.

---

## Safety

- **Pushing to `origin/main`:** on by default for main-target issues. Use `--no-push` until you
  trust a given issue set. Even with `--no-push`, main-target issues are still **closed on GitHub**
  when merged locally.
- **Pushing to existing PR branches:** on by default for branch-target issues. Branch-target issues
  are closed only after Ralph successfully pushes `origin/<target-branch>`. With `--no-push`, Ralph
  leaves the gated integration worktree in place and leaves the issue open.
- **Isolation:** all agent work happens in a throwaway worktree under `.claude/worktrees/`; `main`
  only changes for main-target issues via an explicit `--no-ff` merge after the gates pass.
- **Engine permissions:** Ralph runs the agent with permission checks bypassed
  (`claude --permission-mode bypassPermissions` / `codex exec --dangerously-bypass-approvals-and-sandbox`)
  so it can run unattended. Only run Ralph on a repo and issue set you trust. For Codex, pass
  `--codex-sandbox` or set `CODEX_BYPASS=0` to force `workspace-write` sandboxing for diagnostic
  runs; app builds and simulator access may not work in that mode.
- **Stuck-proofing:** a failed issue is relabelled out of `ready-for-agent`, so the loop can't spin
  on the same failure.

---

## Troubleshooting

- **"built .app not found" / simulator errors** — confirm the iPhone 17 Pro runtime exists, or pass
  `--device "<name>"` / set `SIM_DEVICE` to a unique device (or a UDID if you have duplicates).
- **Build fails only in the loop, not in `swift test`** — the agent likely added files without
  regenerating the Xcode project; the regenerated `WorkoutTracker.xcodeproj` must be committed.
  Check the implement log.
- **Selector returns NONE unexpectedly** — verify `gh auth status` and that issues still carry the
  `ready-for-agent` label (a prior failed run may have moved them to `ready-for-human`).
- **Nothing happens / agent output empty** — check the engine is installed and authenticated
  (`claude --version`, `codex --version`); inspect `ralph/.artifacts/logs/iter-*-select.log`.

---

## Files

```
ralph/
├── ralph.sh            # the loop orchestrator (engine-agnostic)
├── snapshot.sh         # build + launch fixture + capture screenshot
├── prompts/
│   ├── select.md       # SELECT phase: choose one issue
│   ├── implement.md    # IMPLEMENT phase: TDD + non-UI checks only
│   ├── swift-review.md # SWIFT phase: fresh swift-reviewer + remediation
│   └── ui-verify.md    # UI phase: UI tests + screenshot review
└── .artifacts/         # logs, activity.md, screenshots (gitignored)
```

The fixture itself lives in the app: `WorkoutTracker/Fixtures/UITestFixture.swift` and a guarded
branch in `WorkoutTracker/WorkoutTrackerApp.swift`.

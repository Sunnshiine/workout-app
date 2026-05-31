# Ralph — autonomous issue-remediation loop

Ralph runs an AI coding agent (Claude Code **or** Codex) in a loop. Each iteration picks one
GitHub issue labelled `ready-for-agent`, fixes it end-to-end in an isolated git worktree, gates
the result on the full documented testing framework, then merges to `main`, pushes, and closes the
issue. It stops when no eligible issues remain.

It is the issue-driven adaptation of the [Ralph Wiggum loop](https://github.com/coleam00/ralph-loop-quickstart):
GitHub issues replace the quickstart's `prd.md`, and every iteration runs in a **fresh agent
context** so the work never accumulates context bloat.

> ⚠️ **By default Ralph is fully autonomous: it pushes to `origin/main` and closes issues without
> asking.** Read [Safety](#safety) before your first un-gated run. Use `--no-push` while you build trust.

---

## Prerequisites

- **An agent CLI**, at least one of:
  - Claude Code (`claude`) — default engine.
  - Codex (`codex`) — `--engine codex`.
- **`gh`** authenticated against this repo (`gh auth status`). Used to list/close issues and post comments.
- **`xcodegen`** (`brew install xcodegen`) — new Swift files must be added to the project before `xcodebuild` sees them.
- **Xcode 26+** and the **iPhone 17 Pro** simulator runtime (see `../docs/TESTING.md`).
- Run from anywhere inside the repo; the script locates the repo root itself.

---

## Quick start

```bash
# Safest first run: one issue, keep commits local (still closes the issue on GitHub).
ralph/ralph.sh --engine claude --max-iterations 1 --no-push

# Full autonomous run with Claude (pushes to main, closes issues):
ralph/ralph.sh

# Same, driven by Codex:
ralph/ralph.sh --engine codex

# See the inline help:
ralph/ralph.sh --help
```

A good first target is a **pure-logic issue** (no UI), so the run finishes fast and skips the
screenshot gate.

---

## How it works

Each iteration:

```
1. SELECT   An agent lists open `ready-for-agent` issues, skips PRDs/epics, respects
            dependencies, and picks ONE highest-priority unblocked issue.   (read-only)
2. ISOLATE  A fresh worktree + branch `agent/issue-<N>` is created off main.
3. IMPLEMENT The agent reads the issue contract, CONTEXT.md, relevant ADRs, and project
            instructions. It runs Swift Review, and for View/Theme changes UI Screenshot Review,
            during verification. It remediates blocking findings, commits to the branch, and emits
            <promise>COMPLETE</promise>.
4. GATE     The loop independently runs `swift test`, Xcode unit/component tests,
            Xcode UI integration tests, and `swiftlint lint --quiet`.
5. UI GATE  If the change touched Views/Theme, the loop confirms the implementer produced a
            reviewed screenshot artifact.
6. SHIP     Merge the branch into main → push origin (unless --no-push) → close the issue.
7. CLEANUP  Remove the worktree and delete the branch.
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
| `--no-push` | `PUSH=0` | push on | Merge to local `main` only; don't push to origin. |
| `--model NAME` | `MODEL` | `opus` (claude) | Model alias passed to the engine. |
| `--device "..."` | `SIM_DEVICE` | `iPhone 17 Pro` | Simulator for the build + screenshot. |
| `--codex-sandbox` | `CODEX_BYPASS=0` | bypass on | Run Codex in `workspace-write` sandbox instead of full-access unattended mode. This is safer, but Xcode builds and simulator access may fail. |
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

---

## Implementer-Owned Review

Fresh-context review happens inside the implementer's verification loop before it emits
`<promise>COMPLETE</promise>`:

- Claude and Codex implementers must invoke the configured `swift-reviewer` custom agent as a
  separate subagent for Swift code changes, so review comes from a fresh context rather than
  self-review.
- For `WorkoutTracker/Views/` or `WorkoutTracker/Theme.swift` changes, implementers must capture a
  UITEST fixture screenshot with `ralph/snapshot.sh` and invoke the configured
  `ui-screenshot-reviewer` custom agent as a separate subagent.
- Codex CLI supports subagent workflows and custom agents; Ralph expects Codex to spawn the
  configured review agents rather than falling back to copied reviewer instructions.
- Blocking reviewer findings are not final loop failures. The implementer fixes them in the same
  worktree, reruns required checks or screenshot capture, and requests review again before
  completing.
- If the implementer cannot invoke a required review subagent, it must report BLOCKED instead of
  emitting `<promise>COMPLETE</promise>`.

Ralph does not currently set Codex subagent depth. If Codex refuses to spawn a reviewer due to depth
limits, configure Codex `[agents] max_depth` high enough for implementer-owned review subagents.

---

## The UITEST fixture (UI verification)

`swift test` can't exercise SwiftUI views, and a normal launch hits the Google sign-in wall — so
the app supports a `-UITEST_FIXTURE` launch argument (DEBUG only) that boots straight into a
populated `SessionView` using in-memory seeded data and a faked sign-in. No network, no auth, no
real data touched.

`snapshot.sh` uses it to produce a verification screenshot:

```bash
# Screenshot the current working tree:
ralph/snapshot.sh                       # writes ralph/.artifacts/screenshot.png

# Screenshot a specific checkout/worktree, to a chosen path:
PROJECT_DIR=/path/to/worktree ralph/snapshot.sh /tmp/out.png
```

The UI screenshot review only judges what a **static image** can show (layout, missing/clipped
elements, blank screens). It deliberately does **not** fail issues for animations or interaction —
those ride on the build/test gate and Swift review.

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
- UI integration tests: `WorkoutTrackerUITests`.
- Lint: `swiftlint lint --quiet`.
- UI screenshot artifact check: only when `WorkoutTracker/Views/` or `WorkoutTracker/Theme.swift`
  changed. The screenshot review itself happens inside IMPLEMENT via the `ui-screenshot-reviewer`
  subagent.

---

## Safety

- **Pushing to `origin/main`:** on by default. Use `--no-push` until you trust a given issue set.
  Even with `--no-push`, issues are still **closed on GitHub** when merged locally.
- **Isolation:** all agent work happens in a throwaway worktree under `.claude/worktrees/`; `main`
  only changes via an explicit `--no-ff` merge after the gates pass.
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
│   └── implement.md    # IMPLEMENT phase: TDD + review contract
└── .artifacts/         # logs, activity.md, screenshots (gitignored)
```

The fixture itself lives in the app: `WorkoutTracker/Fixtures/UITestFixture.swift` and a guarded
branch in `WorkoutTracker/WorkoutTrackerApp.swift`.

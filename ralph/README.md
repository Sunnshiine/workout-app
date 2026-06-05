# Ralph — Python PR orchestrator

Ralph is the issue-driven automation path for `workout-app`. The Python orchestrator lives under
`ralph/orchestrator`; `ralph/ralph.sh` is a compatibility wrapper for that entrypoint:

```bash
uv run --python 3.11 python -m ralph.orchestrator "$@"
```

The old shell-owned orchestration has been retired. Python owns queue polling, issue selection,
issue contracts, PR targeting, worktrees, phase agents, gates, PR publishing, labels, repair
reports, and blocked rescue state.

Ralph is PR-only. It must not fast-forward, merge, or push `main` directly.

---

## Prerequisites

- `uv` with Python 3.11.
- `gh` authenticated against `Sunnshiine/workout-app`.
- An agent engine for real phase work:
  - primary SDK-forward names: `codex`, `claude` (`openai-codex` and
    `claude-agent-sdk` are installed by `uv`)
  - temporary migration/diagnostic fallback names: `codex-cli`, `claude-cli`
- Existing local agent authentication:
  - `codex` reuses the local Codex account/auth state.
  - `claude` reuses the local Claude Agent/Claude Code account/auth state.
- `Secrets.xcconfig` when Xcode gates are run from generated worktrees.
- Xcode 26+ and the iPhone 17 Pro simulator runtime for app gates.

Ralph does not require `OPENAI_API_KEY`, `CODEX_API_KEY`, `ANTHROPIC_API_KEY`,
`GH_TOKEN`, or `GITHUB_TOKEN`. Use the normal `gh`, Codex, and Claude login flows for
those tools; do not pass raw tokens to Ralph. The only Ralph-specific environment
variable is `SECRETS_XCCONFIG_SOURCE`, which points generated worktrees at a trusted
private `Secrets.xcconfig` source when app gates need it.

---

## Commands

Recommended operator command:

```bash
ralph/ralph.sh --engine codex --max-iterations 1
```

Use `ralph/ralph.sh` for normal runs. It finds the repo root and delegates to the Python module.
Use the Python module directly when you are testing or scripting the Python entrypoint itself.

The wrapper and Python module are otherwise equivalent:

```bash
ralph/ralph.sh --help
uv run --python 3.11 python -m ralph.orchestrator --help
```

Validate configuration without GitHub, git worktrees, or agents:

```bash
ralph/ralph.sh --dry-run
```

Run with a selected engine:

```bash
ralph/ralph.sh --engine codex --max-iterations 1
ralph/ralph.sh --engine claude --max-iterations 1
```

Direct Python invocation:

```bash
uv run --python 3.11 python -m ralph.orchestrator --engine codex --max-iterations 1
```

The normal loop polls `origin/main` at the start of each iteration, selects one eligible
`ready-for-agent` issue, claims it by replacing `ready-for-agent` with `agent-active`, creates a
deterministic `ralph/*` PR branch worktree, runs the phase agents and gates, then publishes only
through a pull request.

### Keep macOS awake with caffeinate

For longer Ralph runs on macOS, wrap the command with the native `caffeinate` utility so the Mac
stays awake until Ralph exits:

```bash
caffeinate -ism ralph/ralph.sh --engine codex --max-iterations 1
```

The useful flags here are:

- `-i` prevents idle system sleep.
- `-m` prevents disk sleep.
- `-s` prevents system sleep while on AC power.

`-d` (prevent display sleep) and `-u` (declare user activity) are optional; keep the copy/paste
command at `-ism` unless you specifically need those behaviors.

To run the Python module directly under `caffeinate`:

```bash
caffeinate -ism uv run --python 3.11 python -m ralph.orchestrator --engine codex --max-iterations 1
```

`caffeinate` exits when the wrapped command exits.

The Python runner supports:

| Flag | Meaning |
|------|---------|
| `--engine fake\|claude\|codex\|claude-cli\|codex-cli` | Engine adapter for phase turns. `codex`/`claude` resolve to SDK clients when their packages import. Dry-run modes force `fake`. |
| `--max-iterations N` / `--max-iter N` | Maximum issues to process. |
| `--model NAME` | Optional model alias passed to the engine. |
| `--device "iPhone 17 Pro"` | Simulator device for app gates. |
| `--implement-timeout-seconds N` | Per-phase agent timeout. |
| `--select-only` | Resolve selection/targets without creating worktrees or running agents. |
| `--repo owner/name` | GitHub repo override. |
| `--dry-run` | No-side-effect config check; no GitHub, worktree, or agent action. |
| `--live-github-dry-run ISSUE` | Controlled fake-engine GitHub wiring proof. |

Removed legacy shell options fail clearly:

- `--publish-target main`, `--publish-target branch`, and `--publish-target auto`
- `--ship-target ...`
- `--no-push`
- `--target-branch`, `--pr-branch`, and `--target-pr`

Use the deterministic Python PR targets instead:

- one-off issue: `ralph/issue-<issue-number>`
- PRD-scoped issue: `ralph/prd-<prd-number>`
- blocked rescue: `ralph/issue-<issue-number>-blocked`

---

## Engine Strategy

Ralph is SDK-forward. The intended/default real engine paths are:

- `codex` -> `CodexSdkEngine`
- `claude` -> `ClaudeSdkEngine`

Those SDK engines run only one agent phase turn. Python still owns issue selection, worktrees,
gates, authority checks, PR publishing, labels, repair loops, and blocked PR state.

The `openai-codex` package drives Codex with `cwd` set to the issue worktree and
`Sandbox.workspace_write`. The `claude-agent-sdk` package drives Claude with `cwd` set to the issue
worktree, one turn per Ralph phase, and edit-oriented Claude Agent permissions. Both clients feed
provider output back into the same Ralph promise-line contract.

The explicit `codex-cli` and `claude-cli` engines are temporary migration and diagnostic fallbacks.
They exist so operators can keep using known-good local agent tooling while SDK auth, permissions,
structured logs, and timeout behavior are proven. If a primary SDK package cannot be imported,
`codex` or `claude` temporarily degrades to the matching CLI adapter; explicit `*-cli` names always
use the CLI adapter. Remove the CLI fallbacks once both SDK engines are stable for unattended local
runs.

---

## Live GitHub Dry-Run

The replacement gate is proven by a controlled live dry-run. It uses the fake engine, so it cannot
invoke Codex, Claude, or any autonomous code-editing agent. It still mutates GitHub state on a
deliberately marked control issue so reviewers can inspect authenticated label, PR, comment,
branch, draft, and ready-state wiring.

Create a temporary control issue with both safeguards:

- title starts with `[Ralph dry-run]`
- body contains the exact line `Ralph live dry-run: authorized`

Then run:

```bash
ralph/ralph.sh \
  --repo Sunnshiine/workout-app \
  --live-github-dry-run <control-issue-number>
```

The command forces `fake`, creates or reuses branch
`ralph/dry-run/issue-<control-issue-number>`, pushes only
`docs/ralph/live-dry-runs/issue-<control-issue-number>.md`, creates or reuses a PR, marks the PR
ready, applies `agent-implemented` to the control issue, applies `agent-ready-for-review` to the
PR, and posts an issue comment.

Current replacement evidence:

- Control issue: `#215`
- PR: `#216`
- Branch: `ralph/dry-run/issue-215`
- Evidence: `docs/ralph/live-dry-runs/issue-215.md`

Close the control issue/PR and delete `ralph/dry-run/issue-*` branches after review.

---

## Issue Lifecycle

Eligible issues are open, labelled `ready-for-agent`, not PRDs/epics, not already claimed or
implemented by Ralph, not `ready-for-human`, and not blocked by unfinished dependencies. A concrete
issue body or Agent Brief must provide the implementation contract.

Ralph treats GitHub labels as its issue lifecycle state machine:

- `ready-for-agent`: selectable by Ralph
- `agent-active`: claimed by Ralph; not selectable by any later loop iteration
- `agent-implemented`: implementation PR exists and is awaiting review/merge
- `ready-for-human`: human decision or implementation needed
- `agent-blocked`: reason label paired with `ready-for-human` after Ralph preserves blocked work

Ralph claims an issue before creating a worktree. If the claim cannot be confirmed, Ralph stops
without running agents.

Python captures an immutable `IssueContract` before any mutating phase:

- issue number, title, body, labels, and context comments
- `PRD: #<number>` membership from the issue body only
- `UI integration test edits: authorized` from the issue body only

On successful PR publication:

- remove `agent-active` and any stale lifecycle labels
- add `agent-implemented`
- leave the issue open
- use `Closes #<issue>` only in the successful integration commit
- let GitHub close the issue when the PR merges

On blocked work:

- remove `agent-active` and any stale implementation labels
- add `ready-for-human`
- add `agent-blocked`
- preserve changed code in a draft rescue PR when code exists
- publish only sanitized summaries, never raw logs or secrets

PR readiness:

- one-off PRs can become ready after their issue passes
- PRD PRs remain draft until every known scoped child is `agent-implemented` and none are
  `ready-for-agent`, `agent-active`, `ready-for-human`, or `agent-blocked`
- ready PRs receive `agent-ready-for-review`

---

## Gates And Authority

Python owns deterministic gates and policy checks. App gate commands remain aligned with
`docs/TESTING.md`:

- `swift test`
- Xcode unit/component tests for `WorkoutTrackerTests`
- Visual Regression tests when Views/Theme changed
- Xcode UI integration tests for `WorkoutTrackerUITests`
- `swiftlint lint --quiet`

Authority policies are mechanical:

- `Tests/UI/**` changes require the pre-agent issue body line
  `UI integration test edits: authorized`.
- UI verification phases may never edit `Tests/UI/**`.
- Added Visual Baselines are allowed.
- Modified Visual Baselines require a saved passing baseline-diff review.
- Deleted Visual Baselines block for human review.

For a first UI-owned gate failure after code exists, Python runs one repair cycle, then either
ships on pass or escalates to a blocked rescue PR on the second failure.

---

## Snapshot Helper

The screenshot helper still builds and launches the UITEST fixture route:

```bash
ralph/snapshot.sh
PROJECT_DIR=/path/to/worktree ralph/snapshot.sh /tmp/out.png
UITEST_ARGS="-UITEST_DEVELOPER_TOOLS" ralph/snapshot.sh /tmp/tools.png
```

Artifacts land under `ralph/.artifacts/`, which is gitignored.

---

## Reports

The read-only telemetry report remains separate from orchestration:

```bash
uv run --python 3.11 python ralph/report.py
uv run --python 3.11 python ralph/report.py --issue 157 --format json
uv run --python 3.11 python ralph/report.py --format csv
```

The report reads local Ralph artifacts and Codex sessions. It does not touch GitHub or git.

---

## Files

```text
ralph/
├── ralph.sh                 # compatibility wrapper for python -m ralph.orchestrator
├── orchestrator/            # Python Ralph state machine and seams
├── prompts/                 # phase prompt templates
├── snapshot.sh              # UITEST fixture screenshot helper
├── report.py                # read-only telemetry report
└── .artifacts/              # logs, activity, screenshots (gitignored)
```

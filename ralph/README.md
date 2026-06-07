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
- For concurrent UI gates, one simulator UDID per Ralph run. Do not point
  multiple agents at the same booted simulator.

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

Issues in a `## Blocked by` chain stack onto an **accreting root PR** rather than each landing on
`main` independently (see [ADR 0008](../docs/adr/0008-ralph-stacked-blocked-by-chains.md)). The
chain root — the eldest ancestor whose own blocker is `None` or already merged — owns the durable
`ralph/issue-<root>` branch. Each dependent is built on a scratch worktree based on that root
branch, and on success its work is squashed back onto the root and a `Closes #<n>` line is appended
to the root PR. A dependent becomes eligible as soon as its dependency is `agent-implemented` (work
is on the root) — it does not wait for a human merge. A dependency that goes `agent-blocked` halts
the whole chain downstream of it. This assumes a single Ralph loop processing one issue at a time.

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
| `--reasoning-effort low\|medium\|high\|xhigh` | Optional whole-run Codex reasoning override. Without it, Ralph uses `gpt-5.5` with `medium` reasoning, except review and UI repair phases use `high`. |
| `--device "iPhone 17 Pro"` | Simulator device for app gates. |
| `--simulator-id UDID` | Specific simulator UDID for app gates. Use this for parallel Ralph runs so each agent owns a different simulator. |
| `--simulator-pool UDID [UDID ...]` | Pool of simulator UDIDs for automatic leasing. Ralph acquires one UDID exclusively per run and releases it on exit. Ignored when `--simulator-id` is given. |
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
- `Blocked by`-chain dependent: the chain root's `ralph/issue-<root-number>` (squashed onto, not a new branch)
- PRD-scoped issue: `ralph/prd-<prd-number>`
- blocked rescue: `ralph/issue-<issue-number>-blocked`

## Parallel UI Gates

Ralph can run at the same time as other Ralph or Codex sessions if each session
targets a distinct simulator UDID. The failure mode to avoid is two agents using
the shared name-based destination `platform=iOS Simulator,name=iPhone 17 Pro`,
which lets Xcode pick the same booted simulator for both UI-test runners.

### Automatic pool leasing (recommended for concurrent runs)

Create a named pool of simulator clones once:

```bash
xcrun simctl list runtimes
xcrun simctl create "Ralph UI 1" "iPhone 17 Pro" "<iOS runtime identifier>"
xcrun simctl create "Ralph UI 2" "iPhone 17 Pro" "<iOS runtime identifier>"
# Note the UDIDs printed by simctl create, or find them with:
xcrun simctl list devices | grep "Ralph UI"
```

Then start concurrent Ralph sessions with the shared pool; each session
automatically acquires an exclusive lease on one UDID:

```bash
ralph/ralph.sh --engine codex --max-iterations 1 --simulator-pool <UDID-1> <UDID-2>
ralph/ralph.sh --engine codex --max-iterations 1 --simulator-pool <UDID-1> <UDID-2>
```

Ralph uses atomic file creation (`O_CREAT|O_EXCL`) in `~/.ralph/simulator-leases/`
to guarantee mutual exclusion: the first process to create `<UDID>.lease` owns that
simulator for its run; the second process takes the next available UDID. If all UDIDs
are busy, the second run fails with a clear error rather than colliding.

Lease files record `{pid, hostname, started_at}`. If a Ralph process is killed, its
lease file is detected as stale (owner PID no longer alive) and reclaimed by the next
run automatically.

### Manual UDID assignment (alternative)

Assign one UDID per session explicitly with `--simulator-id`:

```bash
ralph/ralph.sh --engine codex --max-iterations 1 --simulator-id <UDID-1>
ralph/ralph.sh --engine codex --max-iterations 1 --simulator-id <UDID-2>
```

For raw UI Integration Smoke probes outside Ralph, use the same isolation rule and
keep the selector class-level:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath ".dd-<UDID>" \
  -clonedSourcePackagesDirPath ".spm-<UDID>" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

The UI Interaction Suite remains manual or non-Ralph coverage. Run it only when
higher-flake interaction confidence is explicitly required:

```bash
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath ".dd-<UDID>-interaction" \
  -clonedSourcePackagesDirPath ".spm-<UDID>-interaction" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerInteractionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerAppearanceUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerLongSessionUITests \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerSkipUITests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUITests
```

Clean up only the simulator UDID that the current session owns.

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

A `## Blocked by` dependency counts as satisfied once it is `agent-implemented` **or** `CLOSED` —
both mean its work has landed on the chain root branch (see
[ADR 0008](../docs/adr/0008-ralph-stacked-blocked-by-chains.md)). A dependency that is
`agent-blocked` permanently blocks every transitive dependent.

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

For issues labelled `bug`, Ralph runs a two-turn diagnosis pass before implementation: a reasoning
**diagnose turn** (`diagnose`), then a dedicated **extraction turn** (`diagnose-extract`). The
diagnose turn must build or identify a feedback loop, produce a fix plan, and its full output is
written as the local handoff artifact at `ralph/.artifacts/context/issue-<issue>/diagnosis.md`.
Implementation must read that artifact before editing; review receives it as supporting context.

The diagnose turn also decides whether UI integration test edits are required, but a separate
extraction turn — given the diagnose turn's output inline — has the sole job of reformatting that
decision into one machine-parseable `<diagnosis-result>` artifact: a JSON object carrying the
handoff (`root_cause`, `fix_plan`, `test_seam`) plus the authority decision. Splitting reasoning from
formatting keeps the expensive diagnostic work out of the cheap, mechanical extraction pass:

```text
<diagnosis-result>
{
  "root_cause": "The tap handler never reaches the visible writable row.",
  "fix_plan": "Route the gesture through the real control instead of the overlay.",
  "test_seam": "Tests/UI integration — the visible state only renders in the UI.",
  "ui_integration_test_edits_required": true,
  "scope": ["Tests/UI/WorkoutTrackerUITests.swift"],
  "reason": "Critical real-control workflow per docs/TESTING.md; lower-level tests cannot prove the route."
}
</diagnosis-result>
```

or:

```text
<diagnosis-result>
{
  "root_cause": "<concise statement of the diagnosed cause>",
  "fix_plan": "<intended fix approach>",
  "test_seam": "<lowest layer that can prove the fix, per docs/TESTING.md>",
  "ui_integration_test_edits_required": false
}
</diagnosis-result>
```

If the artifact is missing or malformed, Ralph reruns only the `diagnose-extract` turn — never the
`diagnose` reasoning turn — with the parser error appended, up to two retries (three attempts total),
before escalating for human attention via a blocked rescue PR.

When diagnosis says UI integration test edits are required and the issue body is not already
authorized, Ralph may grant that authority itself before implementation starts. Ralph reuses the
existing `## Test authority` section or appends one, adds the exact marker, records the diagnosis
scope and reason, comments on the issue as an audit event, then recaptures the issue contract before
continuing. The issue body remains the authority source; the comment is only the visible event log;
`diagnosis.md` remains the implementation handoff.

This autonomous authority grant is narrow. Ralph may grant it only during bug diagnosis and only for
paths under `Tests/UI/**`. If diagnosis finds that the correct test also needs `project.yml`,
`Package.swift`, `WorkoutTracker.xcodeproj/project.pbxproj`, scheme files, or other test-target
wiring changes, Ralph must escalate for human authority instead of granting that broader scope.

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
- Xcode UI Integration Smoke for class-level smoke selectors in `WorkoutTrackerUITests`
- `swiftlint lint --quiet`

Authority policies are mechanical:

- `Tests/UI/**` changes require the pre-agent issue body line
  `UI integration test edits: authorized`.
- UI verification phases may never edit `Tests/UI/**`.
- Visual Baselines are normal test artifacts. Ralph does not require special
  authorization or model review for added, modified, or deleted baseline PNGs;
  the Visual Regression test gate is the authority.

For a first UI-owned gate failure after code exists, Python runs one repair cycle, then either
ships on pass or escalates to a blocked rescue PR on the second failure.

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
├── report.py                # read-only telemetry report
└── .artifacts/              # logs, activity, and generated review artifacts (gitignored)
```

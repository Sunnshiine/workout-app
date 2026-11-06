---
name: refactor-parity
description: Diff what the `workout` CLI prints and persists at the merge base against the working tree. Use when a refactor or perf change touches `Sources/WorkoutCLI/`, the `WorkoutApplication` facade, Sheet write planning, or how the CLI home's files are encoded, or before a PR body claims the CLI's behaviour is unchanged.
---

# Refactor parity

<!-- doc-symbols: not-in-tree manifest.json workbook.json -->

`.agents/skills/refactor-parity/parity.sh` (call it `parity.sh` here) builds `workout` at a base
and at the working tree. It runs every `scenarios/*.txt` through both in one fixed home with a
frozen clock. Then it prints a unified diff of stdout, stderr, exit codes, `workbook.json`,
`settings.json`, and `manifest.json`. `parity.sh --help` gives the scenario syntax.

The old binary is the oracle, so parity sees bytes no test asserts: a JSON key, an exit code, a
manifest version, a cell's text. `swift test` still catches most slips first.
`docs/evals/parity-harness.md` has the numbers.

## Steps

1. With `swift test` green, run `git fetch origin`. The default base is the merge base of HEAD and
   `origin/main`, and a stale `origin/main` diffs trunk's own commits. Uncommitted edits are part
   of the head side.
2. From the repo root, run `parity.sh`. A warm run takes about 25 s, and building a new base adds
   10 to 30 s. Add `--keep` to keep the transcripts. The step is done when the last line reads
   `parity: N clean, 0 differ`.
3. Classify every hunk before you change anything:
   - **Bug.** Fix the code and rerun.
   - **Intended.** A new verb or option, a renamed key, or a changed message. The change is not a
     pure refactor. Name each difference in the PR body, and title the PR for what it is.
   - **Skew.** `-- exit 64` on the base side only means base lacks a command head has. Treat it
     as intended, additive surface.
   - **Noise.** Two runs at one commit differ. Pin the source in `parity.sh` the way the home
     path, `WORKOUT_NOW`, `TZ`, and `LC_ALL` are pinned. `parity.sh HEAD` on a clean tree must
     print no diff before you trust a red run. The harness has no masks, so pin the source
     rather than filter the output.
4. Check reach. Grep `scenarios/` for each command, `--scenario`, and cell your change affects.
   When nothing runs it, add a line or a scenario file that does. Plant the slip you are guarding
   against by hand, confirm `parity.sh` goes red, then undo it. The step is done when every path
   the diff touches has a scenario that turns red on a slip there.
5. Cite the clean run from a committed tree:
   `scripts/receipt.sh parity -- .agents/skills/refactor-parity/parity.sh`. Paste the block into
   the PR body as printed.

## Blind spots

A clean run says nothing about these, so cover them with `swift test`, the simulator suites, or
the `verify` skill:

- UI, SwiftUI observation, animation, haptics, and the Live Activity.
- The Exercise History fill, which runs after the CLI process exits.
- A Sheet that refuses a batch or is unreachable, since the local workbook has no fault switch.
- Pending-write diagnostics and the write-target audit ledger, which have no CLI verb.
- `hear`, which the scenarios never run.

The skew rule skips a whole scenario only when base hits a usage error and head hits none. So a
scenario that also runs a command neither side has yet still diffs on base's missing verb.

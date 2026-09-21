# WorkoutTracker verification map

This directory is the maintained source for verifying the user-facing behavior of WorkoutTracker.
Read `../SKILL.md` first for launch, doctor, the drive verbs, and the proof standard. Then read this
index, and use the matching feature file as the recipe. A proof
that drives one convenient entry point is incomplete when the feature file lists others.

## Driving conventions

- A recipe runs top to bottom from the fixture its preconditions name. Any later bullet that launches means `verify.sh stop` first, then `verify.sh launch <fixture>`, with the same `VERIFY_RUN`. That covers another fixture, the same fixture with different flags, and a plain relaunch, because `launch` refuses while any pid it started is alive.
- The trimmed tree cannot prove absence, because a scrolled-out element is missing from it too. Prove an element is gone with `verify.sh find <id>` exiting 1, and a label with `verify.sh tree --all | grep` printing nothing.
- Treat every identifier and label as literal, including the `×` and `·` characters.

## Proof and skip reporting

- The proof standard is `SKILL.md`, Evidence: the changed lines each `shot` prints, the sheet read, and for the CLI the command, stdout, stderr, and exit code.
- Mutation proof adds a second, read-only view of the stored value (the branch leaf, the `Sync status` header, `workout session`, or `workout sheet --cell`).
- Report each proof under its sub-feature ID and the entry point you drove. Report an unreachable path with the attempted command and the unmet precondition. An entry point you skipped stays unverified, whatever another path showed.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with verify.sh` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result. Each bullet starts from the state the one before it leaves. A `Proof` bullet exists only to say what the sheet should show, naming each cell by its shot.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Log a set](./log-a-set.md) covers the active set card: weight, reps, RPE, logging, skipping, reviewing a logged set, exercise history, and the sync side effect.
- [Session queue](./session-queue.md) covers the exercise queue sheet, jumping to an exercise, Up next, and superset pairing.
- [Block overview](./block-overview.md) covers the Block grid, opening another session, making it current, and sessions that are not uploaded.
- [Session completion](./session-completion.md) covers the completion stage, open exercises, Move On from the stage or the queue, and the celebration.
- [Settings](./settings.md) covers appearance, rest timers, switching the training sheet, sync, sign out with pending writes, the build footer, and Developer Tools.
- [Onboarding](./onboarding.md) covers the signed-out wall, choosing a training sheet or pasting its URL, and landing on its freshly synced session.
- [Live Activity](./live-activity.md) covers the rest timer in the Dynamic Island after a logged set, and the Live Activity Lab that raises one from a sample state.
- [Headless CLI](./cli-headless.md) covers the `workout` verbs: init, status, session, log, skip, flush, sheet, sync.

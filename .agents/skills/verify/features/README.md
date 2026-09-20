# WorkoutTracker verification map

This directory is the maintained source for verifying the user-facing behavior of WorkoutTracker.
Read this index before driving the app, then use the matching feature file as the recipe. A proof
that drives one convenient entry point is incomplete when the feature file lists others.

## Baseline preconditions

- `.claude/skills/verify/verify.sh build` has run since the last source change.
- The app is launched with `verify.sh launch <fixture>` and `verify.sh doctor` prints only `ok` lines.
- Every fixture runs on an in-memory store with a faked sign-in, so nothing reaches Google and a relaunch resets everything.
- CLI recipes run against `WORKOUT_HOME=$(mktemp -d)` after `workout init --scenario fresh-block`.
- Never drive an app instance this run did not launch, and never while `scripts/test-sim.sh ui` owns the simulator.

## Driving conventions

- Start every recipe from its named fixture unless its preconditions say otherwise.
- Target elements by accessibility identifier (`tap --id`), then by label, then by coordinates for empty space only.
- Re-read the tree after every action before asserting. `verify.sh tree` and a shot's tree file hold what is on screen; `verify.sh find <id>` answers whether an element exists anywhere, on screen or off. `-UITEST_DISABLE_ANIMATIONS` stops UIKit animations only, so a SwiftUI transition still runs for about 850 ms after a log tap (issue 618). A state absent after one second is still absent. To see a transition, run `verify.sh burst <name> <command>`.
- Treat every identifier and label as literal, including the `×` and `·` characters.
- Run terminal actions through `.build/debug/workout` with `WORKOUT_HOME` exported.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen. Shoot before and after with `verify.sh shot <name>`. The second shot prints the tree lines that changed.
- UI proof is those changed lines, quoted verbatim. For two shots that are not adjacent, run `verify.sh diff <a> <b>`.
- The other half of UI proof is the picture. After the last shot run `verify.sh sheet`, Read the one image it prints, and report by cell number anything the tree cannot show. Overlap, colour, clipping, an element under the status bar. A proof with no sheet is incomplete.
- CLI proof is the command, stdout, stderr, and the exit code.
- Mutation proof includes a second, read-only view of the stored value (the branch dot, the `Sync status` header, `workout session`, or `workout sheet --cell`).
- Record the feature ID and the entry point used with every artifact under `.build/verify/evidence/<run>/`.
- Report an unreachable path with the attempted command and the unmet precondition. Do not report a skipped entry point as verified through another path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with verify.sh` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Log a set](./log-a-set.md) covers the active set card: weight, reps, RPE, logging, skipping, and the sync side effect.
- [Session queue](./session-queue.md) covers the exercise queue sheet, jumping to an exercise, and superset pairing.
- [Block overview](./block-overview.md) covers the Block grid, opening another session, making it current, and sessions that are not uploaded.
- [Session completion](./session-completion.md) covers the completion stage, open exercises, Move On, and the celebration.
- [Settings](./settings.md) covers appearance, rest timers, the training sheet row, sync, sign out with pending writes, and Developer Tools.
- [Onboarding](./onboarding.md) covers choosing a training sheet and landing on its freshly synced session.
- [Headless CLI](./cli-headless.md) covers the `workout` arc: init, session, log, flush, sheet, sync.

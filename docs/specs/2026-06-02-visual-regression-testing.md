# Visual Regression Testing Spec

> Supersession note, 2026-06-05: the Visual layer was adopted, but the
> model-based screenshot reviewer and baseline-diff review policy described in
> the original proposal have been retired. The current policy is in
> [ADR 0007](../adr/0007-visual-regression-testing.md) and
> [docs/TESTING.md](../TESTING.md): Visual Regression tests are the visual gate,
> and Visual Baselines are normal test artifacts.

## Goal

Add a deterministic visual regression gate to the WorkoutTracker test framework so that
AFK agents (the Ralph loop) get hard, byte-level proof that a change did or did not alter
the rendered UI. Today the only visual gate is `ralph/snapshot.sh` → one screenshot →
the `ui-screenshot-reviewer` LLM agent, which is non-deterministic, baseline-free, and
explicitly blind to subtle drift. This spec introduces a **Visual** test layer built on
[`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) that
diffs each glass-bearing view against a committed **Visual Baseline** image and fails
deterministically on any difference.

The first customer is the [WorkoutGlass Primitive refactor](./2026-06-02-workout-glass-primitive.md):
a "pixel-identical" collapse of 36 glass call sites into one helper. The Visual layer is
its proof — every baseline diff must be zero through that refactor.

## Background

The AFK feedback loop is only as strong as its weakest gate. Behavior is well protected
(`swift test`, hosted unit/component tests, UI integration tests, SwiftLint). Visual
correctness is not: per `docs/TESTING.md`, static rendering is checked by one
`ralph/snapshot.sh` screenshot of the seeded `SessionView`, judged by the
`ui-screenshot-reviewer` agent (`~/.claude/agents/ui-screenshot-reviewer.md`). That agent
is instructed to block only for gross breakage (blank/crashed/clipped/missing) and *not*
to block for "minor subjective styling." It has no memory of the prior pixels, so it
cannot catch drift — exactly the failure mode a behavior-preserving refactor like
WorkoutGlass can introduce (a shifted corner radius, spacing, or tint).

PR #166's framework proposal (`docs/proposals/swift-frameworks-reuse-proposal.md`, §3)
recommended **not** adopting `swift-snapshot-testing` yet, on the reasoning that Ralph
screenshots already cover gross visual breakage and that snapshots would add a second
baseline without evidence Ralph is insufficient. This spec **reverses §3** with a
different framing: snapshots are not a second gross-breakage check — they are the
*deterministic regression gate* the LLM reviewer structurally cannot be. That reversal is
recorded in [ADR 0007](../adr/0007-visual-regression-testing.md).

Relevant constraints:

- The View layer assumes iOS 26 with no Liquid Glass fallback ([ADR 0004](../adr/0004-liquid-glass-design-system.md)).
- `WorkoutTracker/Views` is excluded from the SPM library target, so Visual tests cannot
  run under `swift test`; they are xcodebuild-only, hosted in the app target.
- `.glassEffect` is a real-time GPU effect whose offscreen-render determinism is unproven.
- The Sheet-as-source-of-truth model and runtime dependency-light stance must not be
  weakened; `swift-snapshot-testing` enters as a **test-only** dependency.

## Decisions

- **Decision:** Visual regression tests are a deterministic regression gate that
  *complements* `ui-screenshot-reviewer`; they prove existing screens did not drift, while
  the LLM reviewer continues to judge gross breakage and the look of new/changed UI.
  - **Source:** Grilling session, 2026-06-02 (Q1).
  - **Consequence:** Two visual gates with distinct jobs; neither replaces the other.

- **Decision:** Gate the entire adoption on a throwaway **spike** that proves `.glassEffect`
  renders deterministically in the snapshot host on the pinned simulator before any real
  baseline is committed.
  - **Source:** Grilling session, 2026-06-02 (Q2).
  - **Consequence:** If glass renders non-deterministically or blank, the spec falls back to
    perceptual tolerance or to structural snapshots, or the adoption is reassessed — before
    sinking cost into baselines.

- **Decision:** Baseline authority is split. An agent fixing its own code so the diff
  returns to zero (baseline untouched) is the normal loop and is always allowed. An
  *intended* change to an existing screen may be re-recorded by the agent, but the
  old→new diff image is routed to `ui-screenshot-reviewer` against the issue's acceptance
  criteria. Net-new baselines (no prior image) are allowed and covered by the LLM reviewer's
  new-UI judgement.
  - **Source:** Grilling session, 2026-06-02 (Q3).
  - **Consequence:** The agent can self-correct freely, but cannot self-grade a baseline
    change; collateral drift is caught by reviewing the diff, not just the new image.

- **Decision:** Visual tests live in a new dedicated **Visual** test layer (own Xcode
  target), separate from Component (no pixels, unit-speed) and UI (full app launch).
  - **Source:** Grilling session, 2026-06-02 (Q4).
  - **Consequence:** Keeps each gate's job legible; the fast loop stays pixel-free.

- **Decision:** First baselines are **component-level**, one per glass-bearing view across
  all ~12 views WorkoutGlass touches, overriding the proposal's "3-5 tests" cap.
  - **Source:** Grilling session, 2026-06-02 (Q5).
  - **Consequence:** Drift localizes to its source; broader coverage justified by the
    concrete first customer.

- **Decision:** Sequence is spike → baselines on pre-refactor `main` → Visual layer + gate
  → WorkoutGlass refactor as the proving ground (zero diff). The WorkoutGlass spec's "Out"
  line is amended: Visual regression testing is its prerequisite, not separate work.
  - **Source:** Grilling session, 2026-06-02 (Q6).
  - **Consequence:** Baselines capture the *pre*-refactor pixels, so the refactor's
    pixel-identity is actually provable.

- **Decision:** Canonical terms are **Visual Baseline** (the committed reference PNG) and
  **Visual Regression test**; "snapshot" is reserved for the library's own API. Documented
  in `docs/TESTING.md`, not `CONTEXT.md` (these are testing-infrastructure terms, not domain
  language).
  - **Source:** Grilling session, 2026-06-02 (Q7).
  - **Consequence:** No collision with `ralph/snapshot.sh` or `SheetSnapshot`; CONTEXT.md
    untouched.

## Scope

### In

- A new test-only package dependency on `swift-snapshot-testing`.
- A new `WorkoutTracker` Xcode target for the Visual layer (working name
  `WorkoutTrackerSnapshotTests`), hosted in the app target, sourced from `Tests/Visual`.
- A shared, pinned snapshot-trait configuration (device, runtime, color scheme, locale,
  Dynamic Type, precision).
- A spike that proves (or disproves) deterministic glass rendering before real baselines.
- Component-level Visual Baselines for the ~12 glass-bearing views WorkoutGlass touches,
  captured on pre-refactor `main`.
- Ralph loop integration: final-gate execution of the Visual suite plus a baseline git-diff
  authority policy, gated on Views/Theme changes.
- An expansion of the `ui-screenshot-reviewer` charter to adjudicate baseline diffs.
- A new **Visual** layer section in `docs/TESTING.md`.

### Out

- Any change to runtime behavior or to the app's runtime dependency set
  (`swift-snapshot-testing` is test-only).
- Replacing `ralph/snapshot.sh` or retiring `ui-screenshot-reviewer`.
- Multiple states per view beyond one representative state each (added later, only where a
  distinct glass treatment warrants it).
- Dark mode, alternate Dynamic Type sizes, iPad layout, and localization variants of
  baselines (future expansion).
- The WorkoutGlass refactor implementation itself (its own spec).
- Any `CONTEXT.md` change.

## Current Architecture

Test layers and targets today (`project.yml`, `docs/TESTING.md`):

- **Unit** — `Tests/Unit`, runs under `swift test` (SPM library target, Views excluded) and
  in the hosted `WorkoutTrackerTests` bundle.
- **Component** — `Tests/Component`, hosted `WorkoutTrackerTests` bundle, asserts
  presentation/state contracts at unit speed, renders no pixels.
- **UI** — `Tests/UI`, `WorkoutTrackerUITests` ui-testing bundle, launches the app and
  drives real controls.
- **Visual (static)** — `ralph/snapshot.sh` builds + launches a fixture route, captures one
  screenshot; `ui-screenshot-reviewer` judges it and must end in
  `PASS: no blocking static visual findings.`

Ralph gate (Python Ralph via `ralph/ralph.sh`): runs `swift test`, `xcodegen generate`,
`xcodebuild test` for `WorkoutTrackerTests`, `xcodebuild test` for `WorkoutTrackerUITests`,
`swiftlint lint`. When `WorkoutTracker/Views/` or `WorkoutTracker/Theme.swift` changed, it
additionally requires a non-empty screenshot artifact and a saved review artifact whose last
line is the PASS string.

## Target Architecture

Add a fourth test layer:

- **Visual** — `Tests/Visual`, new hosted `WorkoutTrackerSnapshotTests` unit-test bundle
  (so `WorkoutTracker/Views` compiles), depends test-only on `swift-snapshot-testing`.
  Renders glass-bearing views in-process to images and diffs each against its committed
  Visual Baseline. No app launch; not part of `swift test`; not part of the Component
  fast loop.

Ownership and data flow:

- **Visual Baselines** (`Tests/Visual/__Snapshots__/…`) are reviewed artifacts committed to
  the repo. They are the source of truth for "known-good pixels."
- **Per-change (impl phase):** the implementing agent runs only the Visual tests for screens
  it touched; recording is disabled, so a regression fails and stays failed.
- **Final gate (Ralph):** when Views/Theme changed, the loop runs the full Visual suite and
  applies the **baseline authority policy** (below) over the git diff of the baseline
  directory.
- **Baseline-change review:** when a baseline legitimately changes, the old→new diff image
  is handed to `ui-screenshot-reviewer` together with the issue's acceptance criteria.

## Contracts

### Visual Regression test [ADDED]

A test renders one view in one representative state and asserts against its baseline. Shape
(illustrative, not prescriptive):

```swift
@Suite(.snapshots(record: .never))   // verify-only by default; never auto-record in the loop
struct ExerciseSectionVisualTests {
    @Test func glassCard() {
        assertSnapshot(
            of: ExerciseSection(/* deterministic Tests/Support fixture */),
            as: .image(layout: .device(config: .workoutVisualBaseline))
        )
    }
}
```

### Shared trait configuration [ADDED]

A single pinned configuration removes environmental nondeterminism. All Visual tests use it:

- Device / runtime: iPhone 17 Pro, iOS 26.3.1 (the repo baseline).
- Color scheme: light (only).
- Locale: `en_US`.
- Dynamic Type: a fixed default size.
- Precision: exact (`1.0`) by default; perceptual tolerance adopted only if the spike proves
  it necessary.

### Visual Baseline storage [ADDED]

- Location: `Tests/Visual/__Snapshots__/<TestType>/<testName>.png`, committed.
- Treated as a reviewed artifact: a baseline only enters or changes through the authority
  policy below.

### Baseline authority policy (Ralph gate) [ADDED]

Applied over `git diff --name-status` on the baseline directory in `run_full_gate`:

```
A (added baseline)    → allowed   (net-new screen; ui-screenshot-reviewer judges the new UI)
M (modified baseline) → requires the old→new diff to PASS ui-screenshot-reviewer review;
                         otherwise BLOCK + flag human
D (deleted baseline)  → BLOCK + flag human
```

Visual tests always run with recording disabled in the loop, so a failing diff cannot be
silently re-recorded mid-run. A baseline modification is a deliberate, separately reviewed
act.

### `ui-screenshot-reviewer` charter [CHANGED]

The agent gains a second mode: in addition to judging a single fresh screenshot, it
adjudicates a **baseline diff** (old→new image) against the issue's acceptance criteria,
answering "is every changed pixel explained by the issue?" and ending in the existing
`PASS:`/`BLOCK:` line. Its prompt-defense and report-only constraints are unchanged.

## Migration Plan

### Phase 0: Glass determinism spike (throwaway)

- Change: a temporary Visual test that renders one glass-heavy view, records a baseline,
  asserts a zero diff on a second render in the same process, then asserts again after a
  clean build + simulator reboot.
- Compatibility: throwaway; no committed baselines, no gate wiring.
- Acceptance criteria: PASS → proceed. Flaky → evaluate `perceptualPrecision`, document the
  chosen tolerance, then proceed. Blank glass → image baselines cannot prove glass
  pixel-identity; stop and reassess (structural fallback or abandon).
- Outcome (2026-06-03): **deterministic; proceed at exact precision (`1.0`)**.
  - Temporary target/test: `WorkoutTrackerVisualSpikeTests` with one glass-heavy SwiftUI
    view using `.glassEffect` cards and interactive glass pills.
  - Environment: `iPhone 17 Pro` simulator, light mode, `en_US`, fixed Dynamic Type
    `.large`, exact image precision `1.0`. XcodeBuildMCP listed the available runtime as
    `iOS 26.3`.
  - Evidence: after recording the temporary baseline, two `record: .never` renders in the
    same test process passed with zero diff. After `xcodebuildmcp simulator clean`,
    `xcrun simctl shutdown`, `xcodebuildmcp simulator-management boot`, and a fresh test
    run, the same exact-precision assertion passed again.
  - Cleanup: the temporary target, test, dependency, and generated baseline were removed;
    no Visual Baseline is committed by this spike.

### Phase 1: Visual layer infrastructure

- Change: add the `swift-snapshot-testing` test-only dependency; add the
  `WorkoutTrackerSnapshotTests` hosted target (`Tests/Visual`); add the shared trait
  configuration; regenerate the Xcode project; add the target to the `WorkoutTracker`
  scheme; document the **Visual** layer in `docs/TESTING.md`.
- Compatibility: no production code touched; one canonical Visual test proves the target
  builds and runs under xcodebuild.
- Acceptance criteria: `xcodebuild test -only-testing:WorkoutTrackerSnapshotTests` builds
  and passes; `swift test` and the existing targets are unaffected.

### Phase 2: Capture baselines on pre-refactor `main`

- Change: add one component-level Visual Regression test (representative state) for each of
  the ~12 glass-bearing views and commit their baselines, captured on current `main` before
  any WorkoutGlass change.
- Compatibility: tests + baselines only; no production code touched.
- Acceptance criteria: the full Visual suite passes on `main` with a clean diff; every
  glass-bearing view WorkoutGlass touches has a committed baseline.

### Phase 3: Ralph gate integration

- Change: extend `run_full_gate` to run the Visual suite and apply the baseline authority
  policy when Views/Theme changed; wire the baseline-diff review path into the UI
  verification phase; update the `ui-screenshot-reviewer` agent definition for its second
  mode; update `ralph/README.md`.
- Compatibility: additive; the existing screenshot-artifact check remains.
- Acceptance criteria: a deliberately introduced drift on an existing view fails the final
  gate and flags a human; a code-only self-correction that returns the diff to zero passes
  with no baseline change; a net-new baseline passes the add-only rule.

### Phase 4: WorkoutGlass as proving ground

- Change: execute the WorkoutGlass refactor; the Visual suite asserts zero diff across all
  ~12 baselines.
- Compatibility: pure refactor; no intended baseline changes.
- Acceptance criteria: every Visual Baseline diff is zero through the refactor; if any diff
  is non-zero, it is a WorkoutGlass bug to fix in code, never a baseline to re-record.

## Deletion Criteria

- The Phase 0 spike test is deleted once its outcome is recorded in this spec / the ADR.
- No existing visual check is removed: `ralph/snapshot.sh` and the `ui-screenshot-reviewer`
  screenshot pass both remain. Revisit only if the Visual layer proves strictly superior in
  practice — a separate decision, not part of this spec.

## Acceptance Criteria

- [x] Phase 0 spike has a recorded outcome (deterministic / tolerance / fallback).
- [ ] A `WorkoutTrackerSnapshotTests` Visual layer exists and runs under xcodebuild, isolated
      from `swift test` and the Component fast loop.
- [ ] `swift-snapshot-testing` is present as a test-only dependency; the app's runtime
      dependency set is unchanged.
- [ ] Every glass-bearing view WorkoutGlass touches has a committed Visual Baseline captured
      on pre-refactor `main`.
- [ ] The Ralph final gate runs the Visual suite and enforces the baseline authority policy
      when Views/Theme changed.
- [ ] `ui-screenshot-reviewer` adjudicates baseline diffs against issue acceptance criteria.
- [ ] `docs/TESTING.md` documents the Visual layer and the Visual Baseline / Visual
      Regression vocabulary; `CONTEXT.md` is unchanged.
- [ ] The WorkoutGlass refactor lands with a zero diff across all Visual Baselines.

## Testing Strategy

The Visual layer *is* the strategy for visual regression. It is exercised by its own
existence (Phase 1 canonical test), validated against a real change (Phase 3 deliberate
drift must fail), and proven by its first customer (Phase 4 WorkoutGlass zero-diff). Behavior
coverage is unchanged: Unit/Component/UI layers keep their existing duties, and the Visual
layer asserts pixels only — never behavior.

## Open Questions

- Precision policy: resolved by Phase 0. Use exact image precision (`1.0`); no
  `perceptualPrecision` tolerance is required for the initial Visual Baselines.
- Flaky-baseline handling: if a committed baseline later proves intermittently flaky in the
  loop, is the policy to quarantine that single baseline (skip + flag) or to hard-block?
  Defer until the spike establishes the real flakiness floor.

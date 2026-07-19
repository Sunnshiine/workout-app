# ADR 0007: Visual Regression Testing

**Status:** Accepted
**Date:** 2026-06-02
**Amended:** 2026-06-05

## Context

The AFK feedback loop (Ralph) is only as strong as its weakest gate. Behavior is well
protected — `swift test`, hosted unit/component tests, UI integration tests, and SwiftLint
all run in the loop. Visual correctness was not. The old visual gate captured one screenshot
of a fixture route and handed it to an LLM screenshot-review agent. That gate was
non-deterministic, baseline-free, and explicitly instructed not to block for "minor
subjective styling." It had no memory of prior pixels, so it could not detect drift.

That blind spot is precisely where behavior-preserving refactors fail. The imminent
[WorkoutGlass Primitive refactor](../specs/2026-06-02-workout-glass-primitive.md) collapses
36 native Liquid Glass call sites into one helper and claims "pixel-identical output." A
shifted corner radius, spacing, or tint introduced by that refactor would sail through the
current gate.

PR #166's framework proposal (`docs/proposals/swift-frameworks-reuse-proposal.md`, §3)
recommended *not* adopting `swift-snapshot-testing` yet, reasoning that Ralph screenshots
already cover gross visual breakage. That reasoning evaluated snapshots as a *second
gross-breakage check*. It did not weigh them as what they actually are: a deterministic
regression gate that the LLM reviewer structurally cannot be.

## Decision

Adopt visual regression testing via
[`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) as a new
**Visual** test layer, reversing proposal §3. Details are specified in
[the Visual Regression Testing spec](../specs/2026-06-02-visual-regression-testing.md). The
load-bearing decisions:

- **Role.** Visual Regression tests are the deterministic visual gate. They prove covered
  screens did not drift against a committed **Visual Baseline**. Ralph does not use an LLM
  screenshot-review agent to judge screenshots or Visual Baseline diffs.
- **Spike first.** `.glassEffect` is a real-time GPU effect whose offscreen-render
  determinism is unproven. The whole adoption is gated on a throwaway spike proving glass
  renders deterministically on the pinned simulator before any baseline is committed.
- **Baseline treatment.** Visual Baselines are committed test artifacts. Added, modified,
  and deleted baseline PNGs do not require special Ralph authorization or model review; the
  programmatic Visual Regression tests are the gate.
- **Dedicated layer.** Visual tests are a fourth test layer (own Xcode target), distinct
  from Component (no pixels, unit-speed) and UI (full app launch). `swift-snapshot-testing`
  enters as a **test-only** dependency, leaving the runtime dependency-light stance intact.
- **First customer.** Baselines are captured on pre-refactor `main` for the ~12
  glass-bearing views, and the WorkoutGlass refactor is the proving ground: every diff must
  be zero.
- **Vocabulary.** "Visual Baseline" and "Visual Regression test"; "snapshot" is reserved for
  the library API and `SheetSnapshot` meanings. Documented in `docs/TESTING.md`, not
  `CONTEXT.md`.

## Consequences

- The AFK loop gains a hard, deterministic visual gate; behavior-preserving refactors become
  provable rather than vibe-checked.
- New maintenance surface: committed baseline images plus a new test target and dependency.
  Baseline PNG changes are reviewed like other code-review artifacts, not by Ralph-specific
  model review.
- Adoption is contingent on the spike. If glass renders non-deterministically, the fallback
  is perceptual tolerance or structural snapshots — or reassessment — before cost is sunk.
- The Phase 0 spike completed on 2026-06-03. A temporary glass-heavy SwiftUI view rendered
  deterministically at exact image precision (`1.0`) on the available `iPhone 17 Pro`
  simulator runtime reported by XcodeBuildMCP as iOS 26.3, including a second run after
  clean build plus simulator shutdown/boot. Proceed with exact precision; no
  `perceptualPrecision` tolerance is required for the initial baselines.
- The pinned runtime tracks the CI runner image, and the runner is the canonical recorder
  (issue #471: locally-recorded baselines do not transfer across runtimes). Current pin:
  `iPhone 17 Pro` on **iOS 27.0**, the sole runtime the `xcode-27` hosted image ships
  (issue #479; supersedes the iOS 26.3 note above and #471's interim 26.4.1 pin on
  `macos-26`). The determinism spike was re-proven on iOS 27.0 on 2026-07-19: all
  committed baselines plus all 22 Greenhouse Day/Night renders (paper washes, bundled
  Fraunces/Source Sans 3) byte-identical across a simulator reboot and a clean rebuild —
  exact precision stands. Known exception: the two animation-frame fixtures surfaced by
  #471 (`moveOnCelebrationView`, `seededSessionView`) remain nondeterministic until their
  fixtures freeze animation (ticketed separately).
- Proposal §3 is superseded. The proposal's "hard adoption gate" (a package must delete
  app-owned code to earn its place) is consciously not applied here: this dependency is
  test-only and earns its place by strengthening the feedback loop, not by deleting runtime
  code.
- The WorkoutGlass spec's "Out" line is amended — Visual regression testing is its
  prerequisite, not separate work.

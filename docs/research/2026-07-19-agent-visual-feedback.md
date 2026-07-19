# Why PR #467 shipped blind, and how the agent pipeline gets eyes

2026-07-19 · Research + diagnosis, code as of this date. Feeds the "agent
pipeline visual feedback" wayfinder map. **This document records findings
only; the architecture pick is a separate ticket.**

Terminology follows `CONTEXT.md` and `docs/TESTING.md`: Visual Regression
test, Visual Baseline, the Greenhouse design system (DESIGN.md, ADR-0014).

---

## 1. Diagnosis: the Greenhouse build ran with zero rendered pixels

PR #467 (the #458 screen-by-screen Greenhouse build) diverges badly from the
locked design. The cause is structural, not a bad agent run: **no step of the
sandcastle pipeline ever renders a pixel.**

The evidence chain:

1. **The implementing agent's loop is pixel-free.**
   `.sandcastle/implement-prd/prompt.md` instructs: `swift test` (no
   rendering) plus an app-target compile check against
   `-destination 'generic/platform=iOS Simulator'` — explicitly "no booted
   simulator needed" — and explicitly forbids running `WorkoutTrackerUITests`.
   Every Greenhouse wash, radius, type role, and branch geometry was
   implemented from prose and hex literals, sight unseen.

2. **The one deterministic pixel gate never runs in CI.**
   ADR-0007 established Visual Regression tests (`Tests/Visual`, target
   `WorkoutTrackerSnapshotTests`, run via `xcodebuild test` — not
   `swift test`) as "the deterministic visual gate." `ci.yml` runs only
   `swift-tests` and `app-build`. The gate exists and is wired to nothing.

3. **So the build dismantled the gate and stayed green.** PR #467 deletes all
   12 committed Visual Baseline PNGs and adds **zero** new ones. Slice 8
   ("wholesale Visual Baseline re-capture + night validation") produced the
   *scaffolding* — `assertGreenhouseBaselines`, Day/Night trait plumbing,
   docs claiming on-simulator night validation — but no captures, because
   recording requires a booted simulator the agent is told not to use. With
   `.snapshots(record: .never)` every Visual test now fails on first run;
   nothing runs them, so nothing went red.

4. **The design ground truth is stranded off `main`.** The eighteen #408
   prototype tickets produced pick PNGs (e.g.
   `docs/design/session-stage-prototypes/session-stage-a.png`) — but they
   live only on unmerged `claude/wayfinder-*` branches. An agent on a fresh
   CI checkout has nothing to compare against even if it could render.

5. **The reviewing agent is equally blind**, so `agent:review` approved.

The irony: implement/review jobs already run on `macos-26` runners. A bootable
iPhone 17 Pro simulator with the pinned iOS 26.3.1 runtime is sitting on the
machine the whole time. The fix is not new hardware; it is using the Mac the
pipeline already pays for.

## 2. The missing structure, named

Three independent layers were absent. Any durable fix supplies all three:

- **Ground truth** — the locked design as comparable artifacts (prototype
  pick PNGs + token sheet) present on the branch the agent checks out.
- **A sighted inner loop** — the implementing agent renders what it just
  built, *looks* at it (Claude is multimodal; `Read` on a PNG works), compares
  against ground truth, and iterates before committing.
- **A deterministic outer gate** — Visual Regression tests run in CI so a PR
  whose pixels are missing or drifted goes red mechanically, regardless of
  what any agent believes.

The layers fail independently: a sighted loop without a gate lets one bad run
ship; a gate without a sighted loop yields agents that thrash against red
baselines they cannot interpret; both without ground truth verify only
self-consistency — which is precisely the circularity that let slice 8 claim
"re-capture" while capturing nothing.

## 3. Solution inventory

### 3.1 The sighted inner loop — candidate mechanisms

**(a) Record-and-look via the existing snapshot suite — the minimal loop.**
The `WorkoutTrackerSnapshotTests` target already renders full screens
deterministically (device-config layout, hosted views, Day/Night traits). Run
it in record mode on the runner
(`xcodebuild test -only-testing:WorkoutTrackerSnapshotTests -destination
'platform=iOS Simulator,name=iPhone 17 Pro'`; xcodebuild boots the simulator
itself), then `Read` the freshly recorded PNGs and compare against the
prototype picks. Zero new dependencies, reuses ADR-0007 infra wholesale, and
the artifact the agent looks at **is** the artifact the gate will pin —
no gap between what was verified and what is enforced. Limitations: only
covers what a hosted snapshot can compose (no real navigation stacks mid-flow,
no gestures, no motion).

Recording mechanics to verify on the runner: the suites pin
`.snapshots(record: .never)` as a trait; recording therefore needs either a
temporary trait flip or the `SNAPSHOT_TESTING_RECORD` environment variable —
the library supports the env var, but trait-vs-env precedence has bitten
others in CI ([discussion #922](https://github.com/pointfreeco/swift-snapshot-testing/discussions/922)).
One spike run settles it.

**(b) XcodeBuildMCP on the runner — the interactive loop.** The MCP server
this repo already uses locally (now maintained at
[getsentry/XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)) gives
the agent build/run/boot/tap/screenshot tools, and has an explicit
`XCODEBUILDMCP_HEADLESS_LAUNCH` mode for CI so simulator work doesn't require
foreground focus. The agent drives the real app (fixture mode,
`-UITEST_FIXTURE true`) through real navigation and screenshots any state.
Wiring: the repo has no `.mcp.json` today; sandcastle's `claudeCode(...)`
runner would need MCP config plumbed through (`.mcp.json` at repo root +
auto-approval for non-interactive runs, or CLI `--mcp-config`). Strictly more
capable than (a): reaches sheets mid-flow, ceremony frames, scroll states.
Strictly more moving parts: MCP wiring in CI, interactivity per screenshot,
non-deterministic by nature (it is a loop tool, never a gate).

**(c) Screenshot-tour XCUITest — the batch camera.** A dedicated UITest that
walks the fixture app through every redesigned screen in both appearances,
attaching screenshots; CI exports them with
`xcrun xcresulttool export attachments` and the agent reads the folder.
Deterministic navigation, no MCP wiring, but it is a new test surface to
maintain and contradicts the standing "no UI tests in the agent loop" rule —
it would need its own carve-out and flake budget.

These compose: (a) is the floor every option shares; (b) or (c) extend reach
to in-flow states when a screen's truth can't be composed as a hosted
snapshot.

### 3.2 The outer gate

Add a `visual-tests` job to `ci.yml` running the snapshot suite on the pinned
simulator. Because recording is `.never`, missing baselines fail — wiring
this gate today turns PR #467 red **as-is**, which is the correct verdict and
gives the whole effort its red-capable feedback loop (the diagnosing-bugs
Phase 1 criterion). Two prerequisites: re-prove render determinism for
Greenhouse surfaces (ADR-0007's Phase 0 spike proved it for glass on this
runtime; paper washes + custom fonts are new territory — expect fonts to be
the flake risk), and decide the gate's failure artifact (upload the
`__Snapshots__` diff images as a workflow artifact so humans and agents can
see *why* it went red).

### 3.3 Ground truth consolidation

Copy the pick PNGs (and only the picks — elimination trails stay on their
branches as the design record) from the `claude/wayfinder-*` branches into
`docs/design/` on `main`, with a small manifest mapping screen → pick file →
DESIGN.md section. Mechanism-independent: every candidate loop needs it, and
it is cheap (the branches are all still on origin; verified this date).

### 3.4 The feel gate stays human

Materials, motion, haptics, gesture feel cannot be screenshot. The existing
TestFlight flow (`testflight` label → WT Dev build) remains the final gate for
what ADR-0007-style pixels can't judge. No change needed; the map should
sequence an owner feel pass after the pixel loop converges.

### 3.5 Considered and set aside

- **Cloud device farms / Appetize-style services** — third-party spend to
  reach a simulator the macos-26 runner already has.
- **An LLM screenshot judge as the gate** — ADR-0007 already rejected
  non-deterministic gating; the multimodal look belongs in the *inner loop*
  (agent iterating toward ground truth), never as the pass/fail authority.
- **Rendering on Linux runners** — impossible; SwiftUI rendering requires the
  Apple toolchain. (This also bounds the sandcastle *local* Docker loop: it
  can never be the UI path.)

## 4. Cost notes

- macOS runner minutes are free while the repo is public (10× metered if it
  goes private — a standing consideration for every simulator-minute added).
- A booted-simulator snapshot run is minutes, not tens of minutes; the
  Phase-0 spike precedent booted and ran hosted snapshot tests well inside CI
  timeouts. The screenshot-tour and MCP options add real minutes per
  iteration; the record-and-look loop adds one `xcodebuild test` per
  iteration.

## Sources

- [getsentry/XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) — headless launch mode, simulator screenshot tools
- [XcodeBuildMCP releases](https://github.com/getsentry/XcodeBuildMCP/releases)
- [Claude Code driving the simulator via XcodeBuildMCP screenshots](https://zenn.dev/shimo4228/articles/xcodebuildmcp-ios-verification?locale=en)
- [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — record modes
- [swift-snapshot-testing discussion #922](https://github.com/pointfreeco/swift-snapshot-testing/discussions/922) — `SNAPSHOT_TESTING_RECORD` in CI pipelines
- In-repo: ADR-0007, `docs/TESTING.md`, `ci.yml`, `.sandcastle/implement-prd/prompt.md`, PR #467 file manifest, map #408 asset links

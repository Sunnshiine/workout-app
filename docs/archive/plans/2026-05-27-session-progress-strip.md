# Session Progress Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Session progress header with a pinned one-line strip that shows `W1 D1 ›`, one rail segment per Set, and `{remaining} left`.

**Architecture:** Keep progress semantics in the existing pure presentation model in `WorkoutTracker/Progress/ActiveSetPresentation.swift`, then render those semantics in `WorkoutTracker/Views/SessionProgressHeader.swift`. Move the header out of the `ScrollView` in `WorkoutTracker/Views/SessionView.swift` so it remains pinned above the scrolling exercise list. Block Overview routing is not implemented in the current tree, so this plan adds an optional header callback and leaves it nil from `SessionView`.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, SwiftData, Swift Testing, Xcode iOS Simulator.

---

## Current Repo State To Preserve

- Approved spec: `docs/superpowers/specs/2026-05-27-session-progress-strip-design.md`.
- Existing visual direction: `docs/superpowers/specs/2026-05-26-active-set-visual-direction.md`.
- `Package.swift` excludes `WorkoutTracker/Views`, so `swift test` covers the presentation model but not SwiftUI compilation.
- Use `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` for full app compilation.
- At plan-writing time, the worktree contains unrelated changes. Before every commit, run `git status --short` and stage only the files listed in that task.

## File Structure

```
WorkoutTracker/
  Progress/
    ActiveSetPresentation.swift        # modify: compact location, remaining count, rail segment tones
  Theme.swift                          # modify: muted gray and dim rail colors
  Views/
    SessionProgressHeader.swift        # modify: one-line pinned strip UI, rail segments, optional breadcrumb action
    SessionView.swift                  # modify: move header outside ScrollView
WorkoutTrackerTests/
  ActiveSetPresentationTests.swift     # modify: test compact location, remaining count, ordered segment tones
```

## Design Decisions

- The rail uses one `SessionProgressSegmentPresentation` per Set. There is no aggregation, windowing, or bucketing.
- Logged Sets render mint. Skipped Sets count as progressed and render muted gray. The first pending Set renders as an active outlined mint segment. Later pending Sets render dim.
- Remaining work is the number of pending Sets, not `total - logged` only, because skipped Sets also count as progressed.
- The header displays `W{week} D{day} ›`; it does not include Block name and does not display `4 of 12`.
- The rail is display-only. The only possible interaction is the location label, via `onOpenBlockOverview`. `SessionView` passes no callback until `BlockOverviewView` is part of the implemented app.

---

## Task 1: Progress Strip Presentation Model

**Files:**
- Modify: `WorkoutTracker/Progress/ActiveSetPresentation.swift`
- Modify: `WorkoutTrackerTests/ActiveSetPresentationTests.swift`

- [ ] **Step 1: Replace the existing Session header presentation test with strip semantics**

In `WorkoutTrackerTests/ActiveSetPresentationTests.swift`, replace the existing test named `sessionProgressHeaderPresentationShowsBreadcrumbProgressAndRemainingCount` with:

```swift
@MainActor
@Test func sessionProgressHeaderPresentationShowsCompactLocationRemainingCountAndRailSegments() {
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    let week = Week(number: 2)
    let session = Session(dayNumber: 3, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 3, prescribedReps: "3", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]
    week.sessions = [session]
    block.weeks = [week]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.locationText == "W2 D3")
    #expect(presentation.completedSetCount == 2)
    #expect(presentation.totalSetCount == 4)
    #expect(presentation.remainingSetCount == 2)
    #expect(presentation.remainingText == "2 left")
    #expect(presentation.segments.map(\.tone) == [.logged, .skipped, .active, .future])
}
```

- [ ] **Step 2: Add an ordering test for multi-exercise Sessions**

Append this test to `WorkoutTrackerTests/ActiveSetPresentationTests.swift` after the test from Step 1:

```swift
@MainActor
@Test func sessionProgressHeaderPresentationOrdersRailByExerciseOrderThenSetIndex() {
    let session = Session(dayNumber: 1, date: nil)
    let firstExercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    firstExercise.sets = [
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    ]
    let secondExercise = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 1)
    secondExercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .skipped)
    ]
    session.exercises = [secondExercise, firstExercise]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.segments.map(\.tone) == [.logged, .active, .skipped])
    #expect(presentation.segments.map(\.id) == [0, 1, 2])
}
```

- [ ] **Step 3: Run the focused test to verify it fails**

Run:

```bash
swift test --filter ActiveSetPresentation
```

Expected: FAIL with compile errors for `locationText`, `remainingSetCount`, `segments`, and `SessionProgressSegmentTone` not existing yet.

- [ ] **Step 4: Add segment types and replace the header presentation model**

In `WorkoutTracker/Progress/ActiveSetPresentation.swift`, insert these types after `SetRowPresentation` and replace the existing `SessionProgressHeaderPresentation` definition with the code below:

```swift
enum SessionProgressSegmentTone: Equatable, Sendable {
    case logged
    case skipped
    case active
    case future
}

struct SessionProgressSegmentPresentation: Equatable, Identifiable, Sendable {
    let id: Int
    let tone: SessionProgressSegmentTone
}

struct SessionProgressHeaderPresentation: Equatable, Sendable {
    let locationText: String
    let completedSetCount: Int
    let totalSetCount: Int
    let remainingSetCount: Int
    let segments: [SessionProgressSegmentPresentation]

    var remainingText: String {
        "\(remainingSetCount) left"
    }

    init(session: Session) {
        let weekNumber = session.week?.number ?? 0
        locationText = "W\(weekNumber) D\(session.dayNumber)"

        let orderedSets = Self.orderedSets(in: session)
        totalSetCount = orderedSets.count
        completedSetCount = orderedSets.filter(Self.isProgressed).count
        remainingSetCount = orderedSets.filter { $0.state == .pending }.count

        let activeIndex = orderedSets.firstIndex { $0.state == .pending }
        segments = orderedSets.enumerated().map { index, set in
            SessionProgressSegmentPresentation(
                id: index,
                tone: Self.tone(for: set, at: index, activeIndex: activeIndex)
            )
        }
    }

    private static func orderedSets(in session: Session) -> [ExerciseSet] {
        session.exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }
            }
    }

    private static func isProgressed(_ set: ExerciseSet) -> Bool {
        set.state == .logged || set.state == .skipped
    }

    private static func tone(
        for set: ExerciseSet,
        at index: Int,
        activeIndex: Int?
    ) -> SessionProgressSegmentTone {
        switch set.state {
        case .logged:
            return .logged
        case .skipped:
            return .skipped
        case .pending:
            return index == activeIndex ? .active : .future
        }
    }
}
```

- [ ] **Step 5: Run the focused test to verify it passes**

Run:

```bash
swift test --filter ActiveSetPresentation
```

Expected: PASS for all `ActiveSetPresentationTests`.

- [ ] **Step 6: Commit the presentation model slice**

Run:

```bash
git status --short
git add WorkoutTracker/Progress/ActiveSetPresentation.swift WorkoutTrackerTests/ActiveSetPresentationTests.swift
git commit -m "feat: derive session progress strip presentation"
```

Expected: commit succeeds with only the two listed files staged.

---

## Task 2: One-Line Strip View

**Files:**
- Modify: `WorkoutTracker/Theme.swift`
- Modify: `WorkoutTracker/Views/SessionProgressHeader.swift`

- [ ] **Step 1: Add rail colors to Theme**

In `WorkoutTracker/Theme.swift`, add these constants after `static let progressTrack`:

```swift
static let progressStripSkipped = Color.white.opacity(0.32)
static let progressStripFuture = Color.white.opacity(0.14)
```

- [ ] **Step 2: Replace the header view with the mini-strip**

Replace the full contents of `WorkoutTracker/Views/SessionProgressHeader.swift` with:

```swift
import SwiftUI

struct SessionProgressHeader: View {
    let session: Session
    let onOpenBlockOverview: (() -> Void)?

    init(session: Session, onOpenBlockOverview: (() -> Void)? = nil) {
        self.session = session
        self.onOpenBlockOverview = onOpenBlockOverview
    }

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session)
    }

    var body: some View {
        HStack(spacing: 10) {
            location

            SessionProgressRail(segments: presentation.segments)
                .layoutPriority(1)
                .accessibilityHidden(true)

            Text(presentation.remainingText)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(presentation.remainingSetCount) sets left")
    }

    @ViewBuilder
    private var location: some View {
        if let onOpenBlockOverview {
            Button(action: onOpenBlockOverview) {
                locationLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Block Overview")
            .accessibilityValue(presentation.locationText)
        } else {
            locationLabel
                .accessibilityLabel(presentation.locationText)
        }
    }

    private var locationLabel: some View {
        HStack(spacing: 4) {
            Text(presentation.locationText)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    }
}

private struct SessionProgressRail: View {
    let segments: [SessionProgressSegmentPresentation]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(segments) { segment in
                SessionProgressRailSegment(tone: segment.tone)
            }
        }
        .frame(height: 10)
    }
}

private struct SessionProgressRailSegment: View {
    let tone: SessionProgressSegmentTone

    var body: some View {
        Capsule()
            .fill(fill)
            .overlay {
                Capsule()
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            }
            .frame(minWidth: 2, maxWidth: .infinity, minHeight: 8, maxHeight: 8)
    }

    private var fill: Color {
        switch tone {
        case .logged:
            return Theme.accent
        case .skipped:
            return Theme.progressStripSkipped
        case .active:
            return .clear
        case .future:
            return Theme.progressStripFuture
        }
    }

    private var stroke: Color {
        tone == .active ? Theme.accent : .clear
    }

    private var strokeWidth: CGFloat {
        tone == .active ? 1.5 : 0
    }
}
```

- [ ] **Step 3: Run package tests to catch Theme/package regressions**

Run:

```bash
swift test --filter ActiveSetPresentation
```

Expected: PASS. This does not compile `SessionProgressHeader.swift` because `Package.swift` excludes `WorkoutTracker/Views`.

- [ ] **Step 4: Run the app target build to compile the SwiftUI view**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the strip view slice**

Run:

```bash
git status --short
git add WorkoutTracker/Theme.swift WorkoutTracker/Views/SessionProgressHeader.swift
git commit -m "feat: render session progress strip"
```

Expected: commit succeeds with only the two listed files staged.

---

## Task 3: Pin The Strip Above The Scrolling Session

**Files:**
- Modify: `WorkoutTracker/Views/SessionView.swift`

- [ ] **Step 1: Move `SessionProgressHeader` outside the `ScrollView`**

In `WorkoutTracker/Views/SessionView.swift`, replace the current `if let session = workout.displayedSession { ... }` branch with:

```swift
if let session = workout.displayedSession {
    VStack(spacing: 0) {
        SyncStatusBanner(state: sync.state)
            .padding(.top, 8)

        SessionProgressHeader(session: session)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)

        ScrollView {
            GlassEffectContainer(spacing: Theme.cardSpacing) {
                LazyVStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    ForEach(
                        session.exercises.sorted(by: { $0.order < $1.order }),
                        id: \.persistentModelID
                    ) { exercise in
                        ExerciseSection(
                            exercise: exercise,
                            lastPerformedIndex: LastPerformedIndex(context: modelContext),
                            activeSetID: focusManager.activeSetID,
                            activeSetTransition: focusManager.activeSetTransition,
                            retiringTransition: retiringTransition,
                            isCollapsed: focusManager.isCollapsed(exercise),
                            onFocus: { set in
                                focusManager.focus(on: set)
                            },
                            onReexpand: {
                                focusManager.reexpand(exercise)
                            },
                            onLog: { set, log in
                                recordLog(set, as: log, in: session)
                            },
                            onSkip: { set in
                                skip(set, in: session)
                            },
                            onDelete: { set in
                                deleteLog(for: set)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .task(id: session.persistentModelID) {
            focusManager.reset(to: session)
        }
    }
} else {
    EmptyStateView {
        if let id = settings.spreadsheetId {
            await sync.sync(spreadsheetId: id)
            workout.reload()
        }
    }
}
```

- [ ] **Step 2: Verify the app target still builds**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit the pinned layout slice**

Run:

```bash
git status --short
git add WorkoutTracker/Views/SessionView.swift
git commit -m "feat: pin session progress strip"
```

Expected: commit succeeds with only `WorkoutTracker/Views/SessionView.swift` staged.

---

## Task 4: Final Verification

**Files:**
- No code changes.

- [ ] **Step 1: Run all package tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run SwiftLint**

Run:

```bash
swiftlint lint --quiet
```

Expected: no lint violations.

- [ ] **Step 3: Build the iOS app target**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify the strip visually in Simulator**

Use the Build iOS Apps MCP tools to run the app on `iPhone 17 Pro` and check the Session screen:

```text
session_show_defaults
session_set_defaults(projectPath: "/path/to/workout-app/WorkoutTracker.xcodeproj", scheme: "WorkoutTracker", simulatorName: "iPhone 17 Pro", simulatorPlatform: "iOS Simulator", useLatestOS: true)
build_run_sim
screenshot(returnFormat: "path")
```

Expected visual result:
- The strip is visible above the scrollable exercise list.
- The strip sits on the dark app background with no gray panel, grouped container, or floating card.
- The left label reads like `W1 D1 ›`.
- The right label reads like `{remaining} left`.
- There is no `Block · W1 D1` text.
- There is no `4 of 12` text.
- The rail shows one segment per Set.
- Logged segments are mint.
- Skipped segments are muted gray.
- The current or next pending segment is outlined mint.
- Future pending segments are dim.
- Scrolling the exercise list does not scroll the strip away.
- The rail itself has no tap affordance.

- [ ] **Step 5: Check final dirty-tree scope**

Run:

```bash
git status --short
```

Expected: only intentional files from this plan are modified or committed. Existing unrelated changes such as `.claude/settings.json`, `CONTEXT.md`, Xcode user state, older untracked plans, and the approved spec are not staged by this plan unless the user explicitly asks.

---

## Self-Review

**Spec coverage:** Covered pinned top chrome, `W1 D1 ›`, literal per-Set rail, `{remaining} left`, logged/skipped/active/future states, skipped Sets reducing remaining count, no `4 of 12`, no card container, and rail display-only behavior.

**Known gap:** Block Overview navigation is intentionally not wired here because `BlockOverviewView` is not present in the current production Swift files. The header API accepts `onOpenBlockOverview` so the later Block Overview implementation can make only the location label tappable without changing rail semantics.

**Gap scan:** No task contains open-ended implementation gaps. Each code-changing step includes concrete Swift or shell commands.

**Type consistency:** `SessionProgressSegmentTone`, `SessionProgressSegmentPresentation`, `SessionProgressHeaderPresentation.locationText`, `remainingSetCount`, `remainingText`, and `segments` are introduced before the SwiftUI view uses them.

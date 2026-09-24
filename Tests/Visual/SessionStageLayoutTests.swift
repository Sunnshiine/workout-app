import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The `session` fixture's first Session once Set 1 is logged and the focus has moved on, with a rest
/// running, under each height of sync banner (#599). The window is 402pt wide: 874 is the iPhone 17
/// Pro (safe area 62 top and 34 bottom). The shorter windows keep its 62pt top inset and leave about
/// the safe height of a 13 mini (793, 731 safe) and of an SE (709, 647 safe). Frames are global and
/// rounded to whole points.
@MainActor
@Suite
struct SessionStageLayoutTests {
    @Test func theExerciseBranchStaysDrawnUnderARestAndAOneLineBanner() throws {
        let restOnly = try SessionPageHost.layout(.exercise, banner: .outcome(.clear), windowHeight: 874)
        #expect(
            restOnly
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 237, width: 44, height: 44),
                        CGRect(x: 196, y: 255, width: 44, height: 44),
                        CGRect(x: 120, y: 280, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 386, width: 370, height: 18),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: 874)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 736),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 230, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 274, width: 44, height: 44),
                        CGRect(x: 196, y: 286, width: 44, height: 44),
                        CGRect(x: 120, y: 302, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 386, width: 370, height: 18),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func theSupersetStageKeepsItsBranchAtRestAndUnderAOneLineBanner() throws {
        let restOnly = try SessionPageHost.layout(.superset, banner: .outcome(.clear), windowHeight: 874)
        #expect(
            restOnly
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 125, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.superset, banner: .outcome(.writesQueued(1)), windowHeight: 874)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 736),
                    cadence: CGRect(x: 16, y: 175, width: 32, height: 16),
                    name: CGRect(x: 16, y: 205, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 249, width: 125, height: 25),
                    note: CGRect(x: 16, y: 287, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func aDetailHeightBannerTakesLastPerformedAndLeavesTheCardWhereItWas() throws {
        let withDetail = try SessionPageHost.layout(.exercise, banner: .standIn(height: 76), windowHeight: 874)
        #expect(
            withDetail
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 76),
                    stage: CGRect(x: 0, y: 146, width: 402, height: 694),
                    cadence: nil,
                    name: CGRect(x: 16, y: 217, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 272, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 315, width: 44, height: 44),
                        CGRect(x: 196, y: 325, width: 44, height: 44),
                        CGRect(x: 120, y: 340, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func aMiniHeightWindowGivesUpLastPerformedAndKeepsTheBranch() throws {
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: 793)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 689),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 230, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 273, width: 44, height: 44),
                        CGRect(x: 196, y: 282, width: 44, height: 44),
                        CGRect(x: 120, y: 295, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 371, width: 370, height: 308)
                )
        )
    }

    @Test func aTextAndDetailBannerTakesTheSupersetsCadenceAndKeepsItsNote() throws {
        let textAndDetail = try SessionPageHost.layout(.superset, banner: .standIn(height: 54), windowHeight: 874)
        #expect(
            textAndDetail
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 54),
                    stage: CGRect(x: 0, y: 124, width: 402, height: 716),
                    cadence: nil,
                    name: CGRect(x: 16, y: 195, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 239, width: 125, height: 25),
                    note: CGRect(x: 16, y: 278, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func aMiniHeightWindowTakesTheSupersetsNoteAndKeepsItsBranch() throws {
        let oneLine = try SessionPageHost.layout(.superset, banner: .outcome(.writesQueued(1)), windowHeight: 793)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 689),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 219, width: 125, height: 25),
                    note: nil,
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 371, width: 370, height: 308)
                )
        )
    }

    @Test func anSEHeightWindowAtRestGivesUpTheNoteAndKeepsTheBranch() throws {
        let restOnly = try SessionPageHost.layout(.exercise, banner: .outcome(.clear), windowHeight: 709)
        #expect(
            restOnly
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [
                        CGRect(x: 272, y: 194, width: 44, height: 44),
                        CGRect(x: 196, y: 203, width: 44, height: 44),
                        CGRect(x: 120, y: 215, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 287, width: 370, height: 308)
                )
        )
    }

    @Test func anSEHeightWindowKeepsTheNameAndTheCard() throws {
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: 709)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 605),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [],
                    branchIsDrawn: false,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 287, width: 370, height: 308)
                )
        )
    }
}

/// One window shrunk in place, as a rung switch happens at log time, rather than a fresh window per
/// height: a `ViewThatFits` that falls back can leave the lines it dropped in the accessibility tree.
@MainActor
@Suite
struct SessionStageLadderTransitionTests {
    @Test func shrinkingTheWindowDropsEveryLineTheShorterRungGivesUp() throws {
        let pages = try SessionPageHost.layouts(.exercise, banner: .outcome(.writesQueued(1)), windowHeights: [874, 709])
        #expect(
            pages == [
                PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 736),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 230, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 274, width: 44, height: 44),
                        CGRect(x: 196, y: 286, width: 44, height: 44),
                        CGRect(x: 120, y: 302, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 386, width: 370, height: 18),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                ),
                PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 605),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [],
                    branchIsDrawn: false,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 287, width: 370, height: 308)
                )
            ]
        )
    }

    @Test func shrinkingTheCompletionStageDropsTheOpenExercises() throws {
        let labels = try SessionPageHost.completionLabels(windowHeights: [874, 300])
        #expect(
            labels == [
                [
                    "Session complete", "2 sets done across 1 exercise", "Open Exercises",
                    "Back Squat, 1 pending set, W1 D1", "Bench Press, 1 pending set, W1 D2", "1 of 1"
                ],
                ["Session complete", "2 sets done across 1 exercise", "1 of 1"]
            ]
        )
    }
}

private enum StageKind {
    case exercise
    /// Back Squat paired with BB RDL. After Back Squat's Set 1 the focus is on BB RDL, which has a
    /// Cadence line and no Last Performed, and its partner line reads `& Back Squat`.
    case superset
}

/// No banner `text` wraps at this width and the banner does not yet render its `detail` line, so a
/// taller banner is a stand-in of the capsule's height: 54pt is one line of `text` and a `detail`
/// line, 76pt two lines of `text` and a `detail` line.
private enum BannerSlot {
    case outcome(SyncOutcome)
    case standIn(height: CGFloat)
}

private struct PageFrames: Equatable, CustomStringConvertible {
    let banner: CGRect?
    let stage: CGRect?
    let cadence: CGRect?
    let name: CGRect?
    let partner: CGRect?
    let note: CGRect?
    /// The branch's leaf buttons, top to bottom. The Superset branch has no leaf buttons.
    let leaves: [CGRect]
    /// Ink between the last line of words and whatever follows the branch.
    let branchIsDrawn: Bool
    let lastPerformed: CGRect?
    let card: CGRect?

    init(
        banner: CGRect?,
        stage: CGRect?,
        cadence: CGRect?,
        name: CGRect?,
        partner: CGRect?,
        note: CGRect?,
        leaves: [CGRect],
        branchIsDrawn: Bool,
        lastPerformed: CGRect?,
        card: CGRect?
    ) {
        self.banner = banner.map(Self.rounded)
        self.stage = stage.map(Self.rounded)
        self.cadence = cadence.map(Self.rounded)
        self.name = name.map(Self.rounded)
        self.partner = partner.map(Self.rounded)
        self.note = note.map(Self.rounded)
        self.leaves = leaves.map(Self.rounded).sorted { $0.minY < $1.minY }
        self.branchIsDrawn = branchIsDrawn
        self.lastPerformed = lastPerformed.map(Self.rounded)
        self.card = card.map(Self.rounded)
    }

    var description: String {
        let frames = [
            ("banner", banner), ("stage", stage), ("cadence", cadence), ("name", name), ("partner", partner),
            ("note", note), ("lastPerformed", lastPerformed), ("card", card)
        ]
        .map { label, frame in "\(label) \(frame.map(Self.describe) ?? "none")" }
        return (frames + ["leaves [\(leaves.map(Self.describe).joined(separator: "; "))]", "branchIsDrawn \(branchIsDrawn)"])
            .joined(separator: ", ")
    }

    private static func rounded(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded()
        )
    }

    private static func describe(_ frame: CGRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }
}

@MainActor
private final class FrameProbe {
    var stage: CGRect?
}

/// `SessionView`'s arrangement: the banner slot 8pt under the safe top, then the real stage with a
/// stand-in for the 43pt HUD above it and the real rest pill slot below it.
private struct SessionPage: View {
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
    let banner: BannerSlot
    let probe: FrameProbe

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                bannerSlot
                    .padding(.top, 8)

                SessionStageView(
                    session: session,
                    coordinator: coordinator,
                    composition: .reading,
                    actions: .inert,
                    onTopContentOffsetChange: { _ in }
                )
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 43) }
                .restPillInset(restTimer, composition: .reading)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    probe.stage = $0
                }
            }
        }
    }

    @ViewBuilder
    private var bannerSlot: some View {
        switch banner {
        case .outcome(let outcome):
            SyncStatusBanner(outcome: outcome, isSyncing: false)
        case .standIn(let height):
            Color.clear
                .frame(height: height)
                .accessibilityElement()
                .accessibilityLabel("Sync status: stand-in")
                .padding(.horizontal)
        }
    }
}

@MainActor
private enum SessionPageHost {
    static func layout(_ stage: StageKind, banner: BannerSlot, windowHeight: CGFloat) throws -> PageFrames {
        try layouts(stage, banner: banner, windowHeights: [windowHeight])[0]
    }

    /// The page read in one window at each height in turn, resized in place, so a rung switch happens
    /// inside a live hierarchy.
    static func layouts(_ stage: StageKind, banner: BannerSlot, windowHeights: [CGFloat]) throws -> [PageFrames] {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let lastPerformedLookup = LastPerformedLookupStore(context: scenario.context)
        try lastPerformedLookup.ingest(WorkoutFixtureScenarios.backSquatHistory())
        let session = try #require(scenario.store.viewedSession)
        let exercises = session.exercises.sorted { $0.order < $1.order }
        let coordinator = SessionCoordinator(session: session)
        if stage == .superset {
            try #require(coordinator.createSuperset(from: exercises[0], to: exercises[1], in: session))
        }
        let sets = exercises.map { $0.sets.sorted { $0.index < $1.index } }
        try scenario.store.log(sets[0][0], as: SetLog(weight: .pounds(237.5), reps: 5, rpe: .six))
        let nextSet = stage == .superset ? sets[1][0] : sets[0][1]
        coordinator.focus(on: nextSet)
        let focused = try #require(nextSet.exercise)
        let restTimer = RestTimer()
        restTimer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 0), kind: .standard)

        let probe = FrameProbe()
        let page = SessionPage(
            session: session,
            coordinator: coordinator,
            restTimer: restTimer,
            banner: banner,
            probe: probe
        )
        return try read(page, scenario: scenario, lastPerformedLookup: lastPerformedLookup, windowHeights: windowHeights) { window in
            try frames(in: window, focused: focused, probe: probe)
        }
    }

    /// The accessibility labels of the `openExercisesBlock` day's completion stage, with every Set
    /// logged and two Open Exercises from earlier days, read at each window height in turn.
    static func completionLabels(windowHeights: [CGFloat]) throws -> [[String]] {
        let scenario = try WorkoutScenarios.freshConfiguredApp(block: WorkoutFixtureScenarios.openExercisesBlock())
        VisualFixtureRetainer.retain(scenario)
        let session = try #require(scenario.store.viewedSession)
        for set in session.exercises.flatMap(\.sets) where set.isPending {
            try scenario.store.log(set, as: SetLog(weight: .pounds(315), reps: 3, rpe: .eight))
        }
        let page = SessionPage(
            session: session,
            coordinator: SessionCoordinator(session: session),
            restTimer: RestTimer(),
            banner: .outcome(.clear),
            probe: FrameProbe()
        )
        let lookup = LastPerformedLookupStore(context: scenario.context)
        return try read(page, scenario: scenario, lastPerformedLookup: lookup, windowHeights: windowHeights) { window in
            var labels: [String] = []
            _ = window.accessibilityFrames { element in
                if let label = element.accessibilityLabel, !label.isEmpty { labels.append(label) }
                return false
            }
            return labels
        }
    }

    private static func read<Result>(
        _ page: SessionPage,
        scenario: ConfiguredAppScenario,
        lastPerformedLookup: LastPerformedLookupStore,
        windowHeights: [CGFloat],
        _ body: (UIWindow) throws -> Result
    ) throws -> [Result] {
        let hosted =
            page
            .environment(scenario.store)
            .environment(lastPerformedLookup)
            .environment(
                ExerciseHistoryFill(client: VisualNoopSheetsClient(), context: scenario.context, index: lastPerformedLookup)
            )
            .environment(\.themePalette, Theme.palette(for: .day))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        let first = try #require(windowHeights.first)
        return try AccessibilityHost.read(hosted, in: CGSize(width: 402, height: first)) { window in
            try windowHeights.map { height in
                window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
                window.layoutIfNeeded()
                return try body(window)
            }
        }
    }

    private static func frames(in window: UIWindow, focused: Exercise, probe: FrameProbe) throws -> PageFrames {
        func frame(_ matches: (NSObject) -> Bool) -> CGRect? {
            window.accessibilityFrames(where: matches).first
        }
        let cadence = frame { $0.elementIdentifier == "stage-cadence" }
        let name = frame { $0.elementIdentifier == "stage-exercise-name" }
        let partner = frame { $0.elementIdentifier == "superset-partner-name" }
        let note = frame { $0.accessibilityLabel == focused.coachNote }
        let lastPerformed = frame { $0.accessibilityLabel?.hasPrefix("Block ") == true }
        let card = frame { $0.elementIdentifier == "active-set-card" }
        let words = [cadence, name, partner, note].compactMap { $0?.maxY }
        return PageFrames(
            banner: frame { $0.accessibilityLabel?.hasPrefix("Sync status:") == true },
            stage: probe.stage,
            cadence: cadence,
            name: name,
            partner: partner,
            note: note,
            leaves: window.accessibilityFrames { $0.accessibilityLabel.map(isLeafLabel) == true },
            branchIsDrawn: try inkedPixels(
                in: window,
                fromY: words.max() ?? 0,
                toY: (lastPerformed ?? card)?.minY ?? 0
            ) > 1500,
            lastPerformed: lastPerformed,
            card: card
        )
    }

    /// A leaf reads `Set 1, 237.5x5@6`; the card's head reads `Set 2 of 3`.
    private static func isLeafLabel(_ label: String) -> Bool {
        label.hasPrefix("Set ") && label.contains(", ")
    }

    /// Pixels in the band that differ from the page's paper, rendered at the window's scale.
    private static func inkedPixels(in window: UIWindow, fromY top: CGFloat, toY bottom: CGFloat) throws -> Int {
        guard bottom > top else { return 0 }
        let band = CGRect(x: 0, y: top, width: window.bounds.width, height: bottom - top)
        let image = UIGraphicsImageRenderer(bounds: band).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        var pixels = [UInt8](repeating: 0, count: width * cgImage.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: cgImage.height))
        let paper = Array(pixels[0..<3])
        return stride(from: 0, to: pixels.count, by: 4).filter { offset in
            (0..<3).contains { abs(Int(pixels[offset + $0]) - Int(paper[$0])) > 24 }
        }
        .count
    }
}

extension SessionStageActions {
    fileprivate static var inert: SessionStageActions {
        SessionStageActions(
            focus: { _ in },
            log: { _, _ in },
            updateLoggedSet: { _, _ in },
            skip: { _ in },
            delete: { _ in },
            focusSupersetExercise: { _ in },
            dismissSuperset: { _ in },
            showSourceSession: { _ in },
            moveOn: {}
        )
    }
}

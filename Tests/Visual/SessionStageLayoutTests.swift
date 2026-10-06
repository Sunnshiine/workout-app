import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct SessionStageLayoutTests {
    @Test func theExerciseBranchStaysDrawnWithNoBannerAndUnderAOneLineBanner() throws {
        let noBanner = try SessionPageHost.layout(.exercise, banner: .outcome(.clear), windowHeight: WindowHeight.iPhone17Pro)
        #expect(
            noBanner
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 238, width: 44, height: 44),
                        CGRect(x: 196, y: 259, width: 44, height: 44),
                        CGRect(x: 120, y: 286, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: WindowHeight.iPhone17Pro)
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
                        CGRect(x: 272, y: 280, width: 44, height: 44),
                        CGRect(x: 196, y: 301, width: 44, height: 44),
                        CGRect(x: 120, y: 328, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func theSupersetStageKeepsItsBranchWithNoBannerAndUnderAOneLineBanner() throws {
        let noBanner = try SessionPageHost.layout(.superset, banner: .outcome(.clear), windowHeight: WindowHeight.iPhone17Pro)
        #expect(
            noBanner
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
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.superset, banner: .outcome(.writesQueued(1)), windowHeight: WindowHeight.iPhone17Pro)
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
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func aDetailHeightBannerKeepsLastPerformedAndLeavesTheCardWhereItWas() throws {
        let withDetail = try SessionPageHost.layout(.exercise, banner: .twoLinesAndDetail, windowHeight: WindowHeight.iPhone17Pro)
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
                        CGRect(x: 272, y: 318, width: 44, height: 44),
                        CGRect(x: 196, y: 332, width: 44, height: 44),
                        CGRect(x: 120, y: 352, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func aMiniHeightWindowKeepsLastPerformedAndTheBranch() throws {
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: WindowHeight.mini)
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
                        CGRect(x: 272, y: 275, width: 44, height: 44),
                        CGRect(x: 196, y: 289, width: 44, height: 44),
                        CGRect(x: 120, y: 308, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 397, width: 370, height: 18),
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                )
        )
    }

    @Test func aTextAndDetailBannerKeepsTheSupersetsCadenceAndItsNote() throws {
        let textAndDetail = try SessionPageHost.layout(.superset, banner: .textAndDetail, windowHeight: WindowHeight.iPhone17Pro)
        #expect(
            textAndDetail
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 54),
                    stage: CGRect(x: 0, y: 124, width: 402, height: 716),
                    cadence: CGRect(x: 16, y: 195, width: 32, height: 16),
                    name: CGRect(x: 16, y: 225, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 269, width: 125, height: 25),
                    note: CGRect(x: 16, y: 307, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func aOneLineBannerKeepsTheSupersetsLastPerformedAndItsCadence() throws {
        let noBanner = try SessionPageHost.layout(
            .superset,
            banner: .outcome(.clear),
            windowHeight: WindowHeight.iPhone17Pro,
            history: History.backSquatAndBBRDL()
        )
        #expect(
            noBanner
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 125, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(
            .superset,
            banner: .outcome(.writesQueued(1)),
            windowHeight: WindowHeight.iPhone17Pro,
            history: History.backSquatAndBBRDL()
        )
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
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func aMiniHeightWindowKeepsTheSupersetsCadenceNoteAndBranch() throws {
        let oneLine = try SessionPageHost.layout(.superset, banner: .outcome(.writesQueued(1)), windowHeight: WindowHeight.mini)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 689),
                    cadence: CGRect(x: 16, y: 175, width: 32, height: 16),
                    name: CGRect(x: 16, y: 205, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 249, width: 125, height: 25),
                    note: CGRect(x: 16, y: 287, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                )
        )
    }

    @Test func anSEHeightWindowWithNoBannerKeepsTheNoteLastPerformedAndTheBranch() throws {
        let noBanner = try SessionPageHost.layout(.exercise, banner: .outcome(.clear), windowHeight: WindowHeight.se)
        #expect(
            noBanner
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 229, width: 44, height: 44),
                        CGRect(x: 196, y: 236, width: 44, height: 44),
                        CGRect(x: 120, y: 246, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 313, width: 370, height: 18),
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
        )
    }

    @Test func anSEHeightWindowUnderAOneLineBannerGivesUpTheNoteAndLastPerformedButKeepsTheBranch() throws {
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)), windowHeight: WindowHeight.se)
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 605),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [
                        CGRect(x: 272, y: 238, width: 44, height: 44),
                        CGRect(x: 196, y: 249, width: 44, height: 44),
                        CGRect(x: 120, y: 264, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
        )
    }

    @Test func aRunningRestLeavesTheExerciseAndSupersetPagesWhereTheyWere() throws {
        for stage in [StageKind.exercise, .superset] {
            let resting = try SessionPageHost.layout(stage, banner: .outcome(.clear), windowHeight: WindowHeight.iPhone17Pro)
            let notResting = try SessionPageHost.layout(
                stage,
                banner: .outcome(.clear),
                windowHeight: WindowHeight.iPhone17Pro,
                isResting: false
            )
            #expect(resting == notResting, "\(stage) page")
        }
    }
}

@MainActor
@Suite
struct SessionStageLadderTransitionTests {
    @Test func shrinkingTheWindowDropsEveryLineTheShorterRungGivesUp() throws {
        let pages = try SessionPageHost.layouts(
            .exercise,
            banner: .outcome(.writesQueued(1)),
            windowHeights: [WindowHeight.iPhone17Pro, WindowHeight.mini, WindowHeight.se]
        )
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
                        CGRect(x: 272, y: 280, width: 44, height: 44),
                        CGRect(x: 196, y: 301, width: 44, height: 44),
                        CGRect(x: 120, y: 328, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 444, width: 370, height: 18),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 689),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 230, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 275, width: 44, height: 44),
                        CGRect(x: 196, y: 289, width: 44, height: 44),
                        CGRect(x: 120, y: 308, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 397, width: 370, height: 18),
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                ),
                PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 605),
                    cadence: nil,
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [
                        CGRect(x: 272, y: 238, width: 44, height: 44),
                        CGRect(x: 196, y: 249, width: 44, height: 44),
                        CGRect(x: 120, y: 264, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
            ]
        )
    }

    @Test func shrinkingTheCompletionStageDropsTheOpenExercisesAndKeepsMoveOn() throws {
        let heights: [CGFloat] = [WindowHeight.iPhone17Pro, 300]
        let pages = try SessionPageHost.completionPages(windowHeights: heights)
        #expect(
            pages.map(\.labels) == [
                [
                    "Session complete", "1 set done across 1 exercise", "Open Exercises",
                    "Back Squat, 1 pending set, W1 D1", "Move On", "Queue, 1 of 1"
                ],
                ["Session complete", "1 set done across 1 exercise", "Move On", "Queue, 1 of 1"]
            ]
        )
        for (page, height) in zip(pages, heights) {
            let window = CGRect(x: 0, y: 0, width: 402, height: height)
            #expect(page.moveOn.map(window.contains) == true, "Move On lies inside the \(Int(height))pt window")
        }
    }
}

private enum StageKind {
    case exercise
    case superset
}

private enum WindowHeight {
    static let iPhone17Pro: CGFloat = 874
    static let mini: CGFloat = 793
    static let se: CGFloat = 709
}

private enum BannerSlot {
    case outcome(SyncOutcome)
    case standIn(height: CGFloat)

    static let textAndDetail = standIn(height: 54)
    static let twoLinesAndDetail = standIn(height: 76)
}

private enum History {
    static func backSquatAndBBRDL() -> [LastPerformedEntry] {
        WorkoutFixtureScenarios.backSquatHistory() + [
            LastPerformedEntry(
                fullName: "2-3:1:0 BB RDL",
                baseName: "BB RDL",
                resultText: "185x8, 195x8",
                performedOn: Date(timeIntervalSinceReferenceDate: 100),
                source: SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 4, day: 3)).storageValue
            )
        ]
    }
}

private struct PageFrames: Equatable, CustomStringConvertible {
    let banner: CGRect?
    let stage: CGRect?
    let cadence: CGRect?
    let name: CGRect?
    let partner: CGRect?
    let note: CGRect?
    let leaves: [CGRect]
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

private struct CompletionPage {
    let labels: [String]
    let moveOn: CGRect?
}

@MainActor
private final class FrameProbe {
    var stage: CGRect?
}

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
                    restTimer: restTimer
                )
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 43) }
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

/// The coordinator SessionView binds, minus the screen's sync, rest, and motion.
@MainActor
private func boundCoordinator(to session: Session, store: WorkoutStore) -> SessionCoordinator {
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: store,
        sync: InertSessionSync(),
        navigation: store,
        motion: ImmediateSessionMotion(),
        liveEdge: { LiveEdge.resolve(viewedSession: $0, currentSession: store.currentSession) }
    )
    return coordinator
}

private struct InertSessionSync: SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error) {}
    func requestPendingWriteFlush() {}
}

@MainActor
private enum SessionPageHost {
    static func layout(
        _ stage: StageKind,
        banner: BannerSlot,
        windowHeight: CGFloat,
        history: [LastPerformedEntry] = WorkoutFixtureScenarios.backSquatHistory(),
        isResting: Bool = true
    ) throws -> PageFrames {
        try layouts(stage, banner: banner, windowHeights: [windowHeight], history: history, isResting: isResting)[0]
    }

    static func layouts(
        _ stage: StageKind,
        banner: BannerSlot,
        windowHeights: [CGFloat],
        history: [LastPerformedEntry] = WorkoutFixtureScenarios.backSquatHistory(),
        isResting: Bool = true
    ) throws -> [PageFrames] {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let lastPerformedLookup = LastPerformedLookupStore(context: scenario.context)
        try lastPerformedLookup.ingest(history)
        let session = try #require(scenario.store.viewedSession)
        let exercises = session.exercises.sorted { $0.order < $1.order }
        let coordinator = boundCoordinator(to: session, store: scenario.store)
        if stage == .superset {
            try #require(coordinator.createSuperset(from: exercises[0], to: exercises[1], in: session))
        }
        let sets = exercises.map { $0.sets.sorted { $0.index < $1.index } }
        try scenario.store.log(sets[0][0], as: SetLog(weight: .pounds(237.5), reps: 5, rpe: .six))
        let nextSet = stage == .superset ? sets[1][0] : sets[0][1]
        coordinator.focus(on: nextSet)
        let focused = try #require(nextSet.exercise)
        let restTimer = RestTimer()
        if isResting {
            restTimer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 0), kind: .standard)
        }

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

    static func completionPages(windowHeights: [CGFloat]) throws -> [CompletionPage] {
        let scenario = try WorkoutScenarios.freshConfiguredApp(
            block: WorkoutFixtureScenarios.completedSessionWithOpenExercisesBlock()
        )
        VisualFixtureRetainer.retain(scenario)
        let session = try #require(scenario.store.viewedSession)
        let page = SessionPage(
            session: session,
            coordinator: boundCoordinator(to: session, store: scenario.store),
            restTimer: RestTimer(),
            banner: .outcome(.clear),
            probe: FrameProbe()
        )
        let lookup = LastPerformedLookupStore(context: scenario.context)
        return try read(page, scenario: scenario, lastPerformedLookup: lookup, windowHeights: windowHeights) { window in
            CompletionPage(
                labels: window.accessibilityTree.compactMap { $0.accessibilityLabel }.filter { !$0.isEmpty },
                moveOn: window.accessibilityFrames { $0.elementIdentifier == "move-on-button" }.first
            )
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
        return try AccessibilityHost.read(hosted, in: windowHeights.map { CGSize(width: 402, height: $0) }, body)
    }

    private static func frames(in window: UIWindow, focused: Exercise, probe: FrameProbe) throws -> PageFrames {
        func frame(_ matches: (NSObject) -> Bool) -> CGRect? {
            window.accessibilityFrames(where: matches).first
        }
        let cadence = frame { $0.elementIdentifier == "stage-cadence" }
        let name = frame { $0.elementIdentifier == "stage-exercise-name" }
        let partner = frame { $0.elementIdentifier == "superset-partner-name" }
        let note = frame { $0.accessibilityLabel == focused.coachNote }
        let lastPerformed = frame { $0.elementIdentifier == "last-performed-line" }
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

    private static func isLeafLabel(_ label: String) -> Bool {
        label.hasPrefix("Set ") && label.contains(", ")
    }

    private static func inkedPixels(in window: UIWindow, fromY top: CGFloat, toY bottom: CGFloat) throws -> Int {
        guard bottom > top else { return 0 }
        let band = CGRect(x: 0, y: top, width: window.bounds.width, height: bottom - top)
        let image = UIGraphicsImageRenderer(bounds: band).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        var pixels = [UInt8](repeating: 0, count: width * cgImage.height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: cgImage.height))
            let paper = Array(bytes[0..<3])
            return stride(from: 0, to: bytes.count, by: 4).filter { offset in
                (0..<3).contains { abs(Int(bytes[offset + $0]) - Int(paper[$0])) > 24 }
            }
            .count
        }
    }
}

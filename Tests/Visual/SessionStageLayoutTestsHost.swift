import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

enum StageKind {
    case exercise
    case superset
}

enum WindowHeight {
    static let iPhone17Pro: CGFloat = 874
    static let mini: CGFloat = 793
    static let se: CGFloat = 709
    // Measured in 5 pt steps, the single-Exercise stage holds the note rung from 679 to 704 pt
    // and the name and branch rung from 644 to 674 pt.
    static let noteRung: CGFloat = 694
    static let nameAndBranchRung: CGFloat = 659
}

enum History {
    static func backSquatAndBBRDL() -> [LastPerformedEntry] {
        WorkoutFixtureScenarios.backSquatHistory() + [
            LastPerformedEntry(
                exerciseName: "2-3:1:0 BB RDL",
                resultText: "185x8, 195x8",
                performedOn: Date(timeIntervalSinceReferenceDate: 100),
                source: SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 4, day: 3)).storageValue
            )
        ]
    }
}

struct PageFrames: Equatable, CustomStringConvertible {
    var banner: CGRect?
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

    var withoutBanner: PageFrames {
        var page = self
        page.banner = nil
        return page
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

struct CompletionPage {
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
    let banner: SyncOutcome
    let probe: FrameProbe

    var body: some View {
        NavigationStack {
            SessionStageView(
                session: session,
                coordinator: coordinator,
                composition: .reading,
                restTimer: restTimer
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 43)
                    .overlay(alignment: .top) {
                        SyncStatusBanner(outcome: banner, isSyncing: false)
                            .padding(.top, 8)
                    }
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                probe.stage = $0
            }
        }
    }
}

@MainActor
private func boundCoordinator(to session: Session, store: WorkoutStore) -> SessionCoordinator {
    SessionCoordinator(session: session, wiring: .fixture(logging: store, navigation: store))
}

@MainActor
enum SessionPageHost {
    static func layout(
        _ stage: StageKind,
        banner: SyncOutcome,
        windowHeight: CGFloat,
        history: [LastPerformedEntry] = WorkoutFixtureScenarios.backSquatHistory(),
        isResting: Bool = true
    ) throws -> PageFrames {
        try layouts(stage, banner: banner, windowHeights: [windowHeight], history: history, isResting: isResting)[0]
    }

    static func layouts(
        _ stage: StageKind,
        banner: SyncOutcome,
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
            block: WorkbookScenario.completedOpenExercises.block()
        )
        VisualFixtureRetainer.retain(scenario)
        let session = try #require(scenario.store.viewedSession)
        let page = SessionPage(
            session: session,
            coordinator: boundCoordinator(to: session, store: scenario.store),
            restTimer: RestTimer(),
            banner: .clear,
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
            .environment(AppEntryInbox())
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

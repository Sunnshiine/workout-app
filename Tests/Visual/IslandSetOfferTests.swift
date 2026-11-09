import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// Whatever the coach wrote, the target gives way, and the mic, the queue, and every chip draw whole
/// inside the island, at every type size up to where DESIGN.md's Product Scale Rule stops it. From
/// `.xxLarge` the queue leaves the corners for the lines.
@MainActor
@Suite
struct IslandSetOfferLayoutTests {
    @Test(arguments: IslandOffer.all)
    func theOfferKeepsTheMicTheQueueAndEveryChipInsideTheIsland(_ offer: IslandOffer) throws {
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            let drawn = try IslandOffer.drawing(of: offer.state, at: size)

            #expect(
                drawn
                    == IslandDrawing(
                        pastTheEdges: [],
                        controls: offer.controls,
                        queueOnTheLines: size >= .xxLarge
                    ),
                "\(offer) at \(size)"
            )
        }
    }
}

/// The island's bottom region in Night, as production draws it, on the island's black.
@MainActor
@Suite(.snapshots(record: .never))
struct IslandSetOfferVisualTests {
    @Test func theLongestCellsGiveWayAtTheDefaultSize() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .large)
    }

    @Test func theLongestCellsGiveWayAtExtraExtraLarge() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .xxLarge)
    }

    @Test func theLongestCellsGiveWayAtTheLargestType() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .xxxLarge)
    }

    @Test func anOrdinarySetKeepsItsGuidanceAtTheDefaultSize() {
        assertIslandBaseline(IslandOffer.backSquat.state, at: .large)
    }

    private func assertIslandBaseline(
        _ state: WorkoutActivityAttributes.ContentState,
        at size: DynamicTypeSize,
        testName: String = #function
    ) {
        let view = IslandOffer.region(state, at: size).background(.black)
        let bounded = CGSize(width: IslandOffer.regionWidth, height: .greatestFiniteMagnitude)
        let height = UIHostingController(rootView: view).sizeThatFits(in: bounded).height
        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .fixed(width: IslandOffer.regionWidth, height: height),
                traits: UITraitCollection { traits in
                    traits.displayScale = 3
                    traits.userInterfaceStyle = .dark
                }
            ),
            testName: testName
        )
    }
}

struct IslandDrawing: Equatable {
    /// Each element drawn past the island's sides, by its label.
    var pastTheEdges: [String]
    var controls: [String]
    var queueOnTheLines: Bool
}

struct IslandOffer: CustomTestStringConvertible, Sendable {
    /// The width an iPhone 17 Pro gives the expanded island's bottom region: the island measured 374pt
    /// on the iOS 27 simulator, less its 34pt content margins.
    static let regionWidth: CGFloat = 306
    private static let queue = "1 unsynced"
    private static let otherReps = "Other Reps, in the app"

    let name: String
    let state: WorkoutActivityAttributes.ContentState
    let controls: [String]

    var testDescription: String { name }

    static let all = [longestCells, backSquat, longestCellsTheChipsCannotLog]

    static let longestCells = IslandOffer(
        name: "the longest cells",
        state: longest(press: .ready(offer(reps: [1, 2, 3, 4, 5], rpe: ["8", "8.5", "9", "9.5", "10"]))),
        controls: ["Say Set", "1 rep", "2 reps", "3 reps", "4 reps", "5 reps", otherReps]
    )

    static let backSquat = IslandOffer(
        name: "an ordinary Set",
        state: state(
            exerciseName: "Back Squat",
            reps: "5",
            load: "RPE7",
            weight: "252.5",
            guidance: "3:1:1 · Brace hard off the floor, controlled descent.",
            press: .ready(offer(reps: [3, 4, 5, 6, 7], rpe: ["6", "6.5", "7", "7.5", "8"]))
        ),
        controls: ["Say Set", "3 reps", "4 reps", "5 reps", "6 reps", "7 reps", otherReps]
    )

    static let longestCellsTheChipsCannotLog = IslandOffer(
        name: "the longest cells, which the chips cannot log",
        state: longest(press: .needsApp),
        controls: ["Say Set", "Open to log"]
    )

    static func region(_ state: WorkoutActivityAttributes.ContentState, at size: DynamicTypeSize) -> some View {
        IslandSetOffer(state: state)
            .frame(width: regionWidth)
            .environment(\.dynamicTypeSize, size)
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
    }

    @MainActor
    static func drawing(of state: WorkoutActivityAttributes.ContentState, at size: DynamicTypeSize) throws -> IslandDrawing {
        let view = VStack(spacing: 0) {
            region(state, at: size)
            Spacer(minLength: 0)
        }
        let window = CGSize(width: regionWidth, height: 600)
        return try AccessibilityHost.read(view, in: [window]) { window in
            let named = window.accessibilityTree.compactMap { element in
                element.accessibilityLabel.map { (label: $0, frame: element.drawnFrame) }
            }
            let lines = named.first { $0.label.hasPrefix(state.exerciseName) }
            let controls = named.filter { !$0.label.hasPrefix(state.exerciseName) && $0.frame != .zero }
            let drawn = controls + [lines].compactMap { $0 }
            return IslandDrawing(
                pastTheEdges: drawn.filter { $0.frame.minX < -0.5 || $0.frame.maxX > regionWidth + 0.5 }.map(\.label),
                controls: controls.map(\.label),
                queueOnTheLines: lines?.label.contains(queue) ?? false
            )
        }[0]
    }

    private static func longest(press: LoggablePress) -> WorkoutActivityAttributes.ContentState {
        state(
            exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
            reps: "AMRAP",
            load: "Start conservative and work up to a heavy single",
            weight: "1025.5",
            guidance: "2-0-X-1 · Belt off, knee wraps on. Stop the Set the moment the bar speed drops off at all, "
                + "and note how far it slowed",
            press: press
        )
    }

    private static func offer(reps: [Int], rpe: [String]) -> LoggablePress.Offer {
        LoggablePress.Offer(
            repChoices: reps,
            prescribedReps: [],
            rpeChoices: rpe,
            prescribedRPE: nil,
            setIdentity: "visual",
            chosenReps: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func state(
        exerciseName: String,
        reps: String,
        load: String,
        weight: String,
        guidance: String,
        press: LoggablePress
    ) -> WorkoutActivityAttributes.ContentState {
        let restEnd = Date(timeIntervalSinceReferenceDate: 1_000)
        return WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            prescribedReps: reps,
            prescribedLoad: load,
            weightValue: weight,
            weightUnit: "lbs",
            setsDone: 1,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: .dark,
            restStartDate: restEnd.addingTimeInterval(-120),
            restEndDate: restEnd,
            dictation: nil,
            loggablePress: press,
            guidance: guidance,
            start: nil,
            pendingWrites: 1
        )
    }
}

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

    /// The queue never gives way: beside the longest target it draws as wide, at the island's width
    /// and at half of it, as with room to spare, while the target gives way to it.
    @Test func theQueueDrawsWholeWhileTheLongestTargetGivesWay() throws {
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            let widths = try IslandOffer.guidanceLine(at: size, in: [2_000, IslandOffer.regionWidth, IslandOffer.regionWidth / 2])
            let roomy = widths[0]

            for squeezed in widths.dropFirst() {
                #expect(abs(squeezed.queue - roomy.queue) < 0.5, "the queue at \(size), \(squeezed.window)pt")
                #expect(squeezed.target < roomy.target, "the target at \(size), \(squeezed.window)pt")
            }
        }
    }
}

/// How wide the target and the queue draw on the line under the name, in a window of one width.
struct GuidanceLineWidths {
    var window: CGFloat
    var target: CGFloat
    var queue: CGFloat
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

    static let all = [longestCells, backSquat, backSquatAfterARepsTap, longestCellsTheChipsCannotLog]

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
            cadence: "3:1:1",
            coachNote: "Brace hard off the floor, controlled descent.",
            press: .ready(offer(reps: [3, 4, 5, 6, 7], rpe: ["6", "6.5", "7", "7.5", "8"]))
        ),
        controls: ["Say Set", "3 reps", "4 reps", "5 reps", "6 reps", "7 reps", otherReps]
    )

    /// The island needs no Log tap first: its Reps Chips are up on any face but the one a Reps tap
    /// turns to, which shows the RPE Chips.
    static let backSquatAfterARepsTap = IslandOffer(
        name: "an ordinary Set after a Reps tap",
        state: state(
            exerciseName: "Back Squat",
            reps: "5",
            load: "RPE7",
            weight: "252.5",
            cadence: "3:1:1",
            coachNote: "Brace hard off the floor, controlled descent.",
            press: .ready(offer(reps: [3, 4, 5, 6, 7], rpe: ["6", "6.5", "7", "7.5", "8"])),
            face: .rpe(reps: 6)
        ),
        controls: ["Say Set", "6 reps"] + ["6", "6.5", "7", "7.5", "8"].map { "Log 252.5 lbs for 6 at RPE \($0)" }
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

    /// The line under the name with the longest cells' target, queue, and guidance, the target
    /// giving way as in the island's last layout, in a window of each width.
    @MainActor
    static func guidanceLine(at size: DynamicTypeSize, in windows: [CGFloat]) throws -> [GuidanceLineWidths] {
        let state = longestCells.state
        let view = VStack(spacing: 0) {
            IslandGuidanceLine(
                target: state.prescriptionText,
                queue: state.pendingWritesText,
                guidance: state.cadenceAndCoachNote,
                targetGivesWay: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.dynamicTypeSize, size)
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            Spacer(minLength: 0)
        }
        return try AccessibilityHost.read(view, in: windows.map { CGSize(width: $0, height: 200) }) { window in
            let named = window.accessibilityTree.compactMap { element in
                element.accessibilityLabel.map { (label: $0, width: element.drawnFrame.width) }
            }
            let target = try #require(named.first { $0.label.hasPrefix(state.prescriptionText) })
            let drawnQueue = try #require(named.first { $0.label.contains(Self.queue) })
            return GuidanceLineWidths(window: window.frame.width, target: target.width, queue: drawnQueue.width)
        }
    }

    private static func longest(press: LoggablePress) -> WorkoutActivityAttributes.ContentState {
        state(
            exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
            reps: "AMRAP",
            load: "Start conservative and work up to a heavy single",
            weight: "1025.5",
            cadence: "2-0-X-1",
            coachNote: "Belt off, knee wraps on. Stop the Set the moment the bar speed drops off at all, and note how far it slowed",
            press: press
        )
    }

    private static func offer(reps: [Int], rpe: [String]) -> LoggablePress.Offer {
        LoggablePress.Offer(
            repChoices: reps,
            prescribedReps: [],
            rpeChoices: rpe,
            prescribedRPE: nil,
            setIdentity: "visual"
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func state(
        exerciseName: String,
        reps: String,
        load: String,
        weight: String,
        cadence: String,
        coachNote: String,
        press: LoggablePress,
        face: LockScreenCardFace = .rest
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
            readbackStaysOffTheCard: nil,
            loggablePress: press,
            cardFace: face,
            cardStats: [],
            cadence: cadence,
            coachNote: coachNote,
            start: nil,
            pendingWrites: 1
        )
    }
}

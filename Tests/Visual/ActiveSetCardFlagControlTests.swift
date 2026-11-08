import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@Observable
private final class CardPosition {
    var stop = 0
}

/// The card stays one view as the athlete moves between Sets, so its flag has to follow the Set on it.
@MainActor
@Suite
struct ActiveSetCardFlagControlTests {
    private struct Stop {
        let set: ExerciseSet
        let mode: SetCardSlot.Mode
    }

    private struct MovingCard: View {
        let position: CardPosition
        let stops: [Stop]

        var body: some View {
            let stop = stops[position.stop]
            VStack(spacing: 0) {
                ActiveSetCard(
                    set: stop.set,
                    setOrdinal: stop.set.index + 1,
                    setCount: stops.count,
                    mode: stop.mode,
                    mic: nil,
                    onLog: { _ in },
                    onSkip: {},
                    onDelete: {},
                    onFlag: {},
                    onTouchWhileHeld: {},
                    onClearMenuOpened: {},
                    onClearMenuClosed: {}
                )
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        }
    }

    private struct FlagControl: Equatable {
        let label: String
        let value: String
    }

    private static let review = SetCardSlot.Mode.reviewingLogged(showsSavedConfirmation: false)

    private func loggedSet(index: Int, flag: SetFlag?) -> ExerciseSet {
        let set = ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
        set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
        if let flag {
            set.record(flag, standing: .unsynced)
        }
        return set
    }

    private func pendingSet(index: Int) -> ExerciseSet {
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    }

    private func flagControl(in window: UIWindow) -> FlagControl? {
        window.accessibilityTree.first { $0.elementIdentifier == "set-flag-control" }.map {
            FlagControl(label: $0.accessibilityLabel ?? "", value: $0.accessibilityValue ?? "")
        }
    }

    /// What the card's flag control says on each stop, in order, moving the one card along them.
    private func flagControls(across stops: [Stop]) throws -> [FlagControl?] {
        let exercise = Exercise(name: "Competition Bench Press", coachNote: nil)
        exercise.sets = stops.map(\.set)
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let position = CardPosition()
        let view = MovingCard(position: position, stops: stops)
            .environment(LastPerformedLookupStore(context: scenario.context))
            .environment(\.themePalette, Theme.palette(for: .day))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        let controls = try AccessibilityHost.read(view, in: [CGSize(width: 402, height: 874)]) { window in
            stops.indices.map { stop in
                position.stop = stop
                CFRunLoopRunInMode(.defaultMode, 0.1, false)
                window.layoutIfNeeded()
                return flagControl(in: window)
            }
        }
        withExtendedLifetime(exercise) {}
        return controls[0]
    }

    @Test func aPendingSetAfterAFlaggedOneShowsNoFlagControl() throws {
        let controls = try flagControls(across: [
            Stop(set: loggedSet(index: 0, flag: SetFlag(kind: .pain, text: "left hip")), mode: Self.review),
            Stop(set: pendingSet(index: 1), mode: .logging)
        ])

        #expect(controls == [FlagControl(label: "Flag Set 1", value: "Unsynced"), nil])
    }

    @Test func aFlaggedSetAfterAPendingOneShowsItsOwnFlagControl() throws {
        let controls = try flagControls(across: [
            Stop(set: pendingSet(index: 0), mode: .logging),
            Stop(set: loggedSet(index: 1, flag: SetFlag(kind: .pain, text: "left hip")), mode: Self.review)
        ])

        #expect(controls == [nil, FlagControl(label: "Flag Set 2", value: "Unsynced")])
    }

    @Test func movingBetweenTwoLoggedSetsNamesTheSetOnTheCard() throws {
        let controls = try flagControls(across: [
            Stop(set: loggedSet(index: 0, flag: SetFlag(kind: .pain, text: "left hip")), mode: Self.review),
            Stop(set: loggedSet(index: 1, flag: nil), mode: Self.review)
        ])

        #expect(
            controls == [
                FlagControl(label: "Flag Set 1", value: "Unsynced"),
                FlagControl(label: "Flag Set 2", value: "")
            ]
        )
    }
}

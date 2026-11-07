import AppIntents
import Foundation
import Testing

@testable import WorkoutTracker

/// Hosted only: the intent and the content state live beside the Live Activity's attributes, which
/// the app and the widget compile and `swift test` does not.
@Suite
struct LogSetAtRPEIntentTests {
    /// Background mode is what lets a chip run on a locked phone with the app staying behind, and
    /// the default authentication policy is what lets it run without an unlock.
    @Test func aChipRunsInTheBackgroundWithoutAuthentication() {
        #expect(LogSetAtRPEIntent.supportedModes == .background)
        #expect(LogSetAtRPEIntent.authenticationPolicy == .alwaysAllowed)
    }

    /// ActivityKit refuses content over 4 KB, which would freeze the card on the Set before.
    @Test func theLongestCardFitsActivityKitsLimit() throws {
        let longName = String(repeating: "Competition Pause Tempo Squat ", count: 3)
        let setIdentity = LoggableSetIdentity(
            session: SessionCoordinate(
                blockTab: String(repeating: "Block 27 Peaking ", count: 6),
                address: SessionAddress(week: 12, day: 7)
            ),
            setID: ActiveSetID(exerciseOrder: 99, setIndex: 99),
            weight: .pounds(1237.5),
            reps: 100
        ).storageValue
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: longName,
            prescribedReps: "AMRAP then 3 x 5 at a slow descent",
            prescribedLoad: "RPE7.5 after a top single at RPE9, then back off",
            weightValue: "1237.5",
            weightUnit: "lb",
            setsDone: 99,
            setsTotal: 100,
            variant: .restTimerSetsLeft,
            appearance: .dark,
            restStartDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 800_000_300),
            dictation: .logged(
                "1237.5×100 @9.5",
                to: LiveActivityWrittenSet(exerciseName: longName, setOrdinal: 99, setsTotal: 100)
            ),
            loggablePress: .ready(
                LoggablePress.Offer(
                    weight: "1237.5",
                    reps: 100,
                    rpeChoices: ["8", "8.5", "9", "9.5", "10"],
                    prescribedRPE: "9.5",
                    setIdentity: setIdentity
                )
            ),
            lastPerformed: Array(repeating: String(repeating: "x", count: 120), count: 5),
            pendingWrites: 99
        )

        #expect(try JSONEncoder().encode(state).count < 4096)
    }

    @Test(
        arguments: [
            ("5", "RPE7", "252.5", 5, nil),
            ("5", "RPE 7", "252.5", 5, nil),
            ("5", "RPE9", "252.5", 5, "RPE9"),
            ("5", "80%", "252.5", 5, "80%"),
            ("12", "BW", "BW", 12, nil),
            ("5", "225", "225", 5, nil),
            ("3-5", "RPE7", "225", 5, "3-5 reps"),
            ("5", "225", "240", 3, "5 reps / 225")
        ] as [(String, String, String, Int, String?)]
    )
    func besideTheValuesThePrescriptionKeepsOnlyWhatTheChipsDoNotState(
        reps: String,
        load: String,
        weight: String,
        logged: Int,
        expected: String?
    ) {
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: "Back Squat",
            prescribedReps: reps,
            prescribedLoad: load,
            weightValue: weight,
            weightUnit: "lb",
            setsDone: 0,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: .dark,
            restStartDate: nil,
            restEndDate: nil,
            dictation: nil,
            loggablePress: .needsApp,
            lastPerformed: [],
            pendingWrites: 0
        )
        let offer = LoggablePress.Offer(
            weight: weight,
            reps: logged,
            rpeChoices: ["6", "6.5", "7", "7.5", "8"],
            prescribedRPE: load.contains("RPE") ? String(load.filter { $0.isNumber || $0 == "." }) : nil,
            setIdentity: ""
        )

        #expect(state.prescription(beyond: offer) == expected)
    }
}

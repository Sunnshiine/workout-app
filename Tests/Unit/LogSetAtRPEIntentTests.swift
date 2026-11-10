import AppIntents
import Foundation
import Testing

@testable import WorkoutTracker

/// Hosted only: the intents and the content state live beside the Live Activity's attributes, which
/// the app and the widget compile and `swift test` does not.
@Suite(.serialized)
@MainActor
struct LogSetAtRPEIntentTests {
    /// Background mode is what lets a chip run on a locked phone with the app staying behind, and
    /// the default authentication policy is what lets it run without an unlock.
    @Test func bothChipsRunInTheBackgroundWithoutAuthentication() {
        #expect(ChooseRepsIntent.supportedModes == .background)
        #expect(ChooseRepsIntent.authenticationPolicy == .alwaysAllowed)
        #expect(LogSetAtRPEIntent.supportedModes == .background)
        #expect(LogSetAtRPEIntent.authenticationPolicy == .alwaysAllowed)
    }

    /// ActivityKit refuses content over 4 KB, which would freeze the card on the Set before.
    @Test func theLongestCardFitsActivityKitsLimit() throws {
        let longName = String(repeating: "Competition Pause Tempo Squat ", count: 3)
        let session = SessionCoordinate(
            blockTab: String(repeating: "Block 27 Peaking ", count: 6),
            address: SessionAddress(week: 12, day: 7)
        )
        let setID = ActiveSetID(exerciseOrder: 99, setIndex: 99)
        let setIdentity = LoggableSetIdentity(session: session, setID: setID, weight: .pounds(1237.5)).storageValue
        let start = AppEntryRequest.startTimedEffort(CountdownRun.Owner(session: session, set: setID))
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: longName,
            prescribedReps: "AMRAP then 3 x 5 at a slow descent",
            prescribedLoad: "RPE7.5 after a top single at RPE9, then back off",
            weightValue: "1237.5",
            weightUnit: "lbs",
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
                    repChoices: [96, 97, 98, 99, 100],
                    prescribedReps: [96, 97, 98, 99, 100],
                    rpeChoices: ["8", "8.5", "9", "9.5", "10"],
                    prescribedRPE: "9.5",
                    setIdentity: setIdentity,
                    chosenReps: 100
                )
            ),
            cadence: "10-20:10-20:10-20",
            coachNote: String(repeating: "x", count: 120),
            start: LockScreenStartOffer(label: "120 s hold", spokenLabel: "120 second hold", url: start.url),
            pendingWrites: 99
        )

        #expect(try JSONEncoder().encode(state).count < 4096)
    }

    @Test(
        arguments: [
            ("235", "lbs", "235 lbs"),
            ("237.5", "lbs", "237.5 lbs"),
            ("BW", "", "BW")
        ]
    )
    func theCardPrintsTheWeightTheStageHolds(value: String, unit: String, expected: String) {
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: "Back Squat",
            prescribedReps: "5",
            prescribedLoad: "RPE 7",
            weightValue: value,
            weightUnit: unit,
            setsDone: 0,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: .dark,
            restStartDate: nil,
            restEndDate: nil,
            dictation: nil,
            loggablePress: .needsApp,
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: 0
        )

        #expect(state.weightText == expected)
    }

    /// The card's two taps reach the app's performer as the athlete made them: the Reps alone, then
    /// the Reps with the RPE, and nil from the chip that turns the row back.
    @Test func eachChipHandsItsTapToTheApp() async throws {
        let spy = PressSpy()
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = spy
        defer { LockScreenPresses.performer = registered }

        _ = try await ChooseRepsIntent(setIdentity: "Set", reps: 6).perform()
        _ = try await ChooseRepsIntent(setIdentity: "Set", reps: nil).perform()
        _ = try await LogSetAtRPEIntent(setIdentity: "Set", reps: 6, rpe: "7.5").perform()

        #expect(spy.presses == ["reps Set 6", "reps Set nil", "log Set 6 7.5"])
    }

    /// The widget extension registers no performer, so a press that runs there fails rather than
    /// writing nothing quietly.
    @Test func aChipWithNoPerformerFailsLoudly() async {
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = nil
        defer { LockScreenPresses.performer = registered }

        await #expect(throws: LockScreenPresses.PerformedOutsideTheApp.self) {
            _ = try await ChooseRepsIntent(setIdentity: "Set", reps: 6).perform()
        }
        await #expect(throws: LockScreenPresses.PerformedOutsideTheApp.self) {
            _ = try await LogSetAtRPEIntent(setIdentity: "Set", reps: 6, rpe: "7").perform()
        }
    }
}

@MainActor
private final class PressSpy: LockScreenPressPerforming {
    private(set) var presses: [String] = []

    func chooseReps(setIdentity: String, reps: Int?) async {
        presses.append("reps \(setIdentity) \(reps.map(String.init) ?? "nil")")
    }

    func logSet(setIdentity: String, reps: Int, rpe: String) async {
        presses.append("log \(setIdentity) \(reps) \(rpe)")
    }
}

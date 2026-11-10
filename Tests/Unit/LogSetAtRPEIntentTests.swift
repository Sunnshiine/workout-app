import AppIntents
import Foundation
import Testing

@testable import WorkoutTracker

/// Hosted only: the intents and the content state live beside the Live Activity's attributes, which
/// the app and the widget compile and `swift test` does not.
@Suite(.serialized)
@MainActor
struct LogSetAtRPEIntentTests {
    /// Background mode is what lets a press run on a locked phone with the app staying behind, and
    /// the default authentication policy is what lets it run without an unlock.
    @Test func bothPressesRunInTheBackgroundWithoutAuthentication() {
        #expect(TurnLockScreenCardIntent.supportedModes == .background)
        #expect(TurnLockScreenCardIntent.authenticationPolicy == .alwaysAllowed)
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
                    setIdentity: setIdentity
                )
            ),
            cardFace: .rpe(reps: 100),
            cardStats: [
                LockScreenCardStat(label: "lbs", value: "1,237.5", spoken: "1237.5 pounds", isMissing: false),
                LockScreenCardStat(
                    label: "reps",
                    value: "AMRAP then 3 x 5 at a slow descent",
                    spoken: "AMRAP then 3 x 5 at a slow descent Reps",
                    isMissing: false
                ),
                LockScreenCardStat(label: "RPE", value: "9.5", spoken: "RPE 9.5", isMissing: false)
            ],
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
            cardFace: .rest,
            cardStats: [],
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: 0
        )

        #expect(state.weightText == expected)
    }

    /// Each control's tap reaches the app's performer as the athlete made it: the face it turns to
    /// with the Set it is about, then the Reps with the RPE.
    @Test func eachControlHandsItsTapToTheApp() async throws {
        let spy = PressSpy()
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = spy
        defer { LockScreenPresses.performer = registered }

        _ = try await TurnLockScreenCardIntent(to: .coachNote).perform()
        _ = try await TurnLockScreenCardIntent(to: .rest).perform()
        _ = try await TurnLockScreenCardIntent(to: .reps, pressing: "Set").perform()
        _ = try await TurnLockScreenCardIntent(to: .rpe(reps: 6), pressing: "Set").perform()
        _ = try await LogSetAtRPEIntent(setIdentity: "Set", reps: 6, rpe: "7.5").perform()

        #expect(spy.presses == ["turn coachNote", "turn rest", "turn reps Set", "turn rpe 6 Set", "log Set 6 7.5"])
    }

    /// A press whose face the card has not got fails rather than turning the card somewhere else.
    @Test func aTurnToNoFaceFailsLoudly() async {
        let spy = PressSpy()
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = spy
        defer { LockScreenPresses.performer = registered }
        let intent = TurnLockScreenCardIntent()
        intent.face = "sideways"

        await #expect(throws: LockScreenPresses.UnreadableFace.self) {
            _ = try await intent.perform()
        }
        #expect(spy.presses.isEmpty)
    }

    /// The widget extension registers no performer, so a press that runs there fails rather than
    /// writing nothing quietly.
    @Test func aPressWithNoPerformerFailsLoudly() async {
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = nil
        defer { LockScreenPresses.performer = registered }

        await #expect(throws: LockScreenPresses.PerformedOutsideTheApp.self) {
            _ = try await TurnLockScreenCardIntent(to: .reps, pressing: "Set").perform()
        }
        await #expect(throws: LockScreenPresses.PerformedOutsideTheApp.self) {
            _ = try await LogSetAtRPEIntent(setIdentity: "Set", reps: 6, rpe: "7").perform()
        }
    }

    /// The Lock Screen draws what the app chose, so the face and the numbers cross to the activity
    /// whole, and a rest read back off a running activity is still on the face it showed.
    @Test func theActivityCarriesTheFaceAndTheNumbersBothWays() throws {
        let turned = try #require(Self.squatRest.turned(to: .rpe(reps: 6)))

        let state = WorkoutActivityAttributes.ContentState(restContent: turned, dictation: nil)

        #expect(state.face == .rpe(reps: 6))
        #expect(state.stats.map(\.value) == ["1,002.5", "5", "7"])
        #expect(state.weightOnTheCard == "1,002.5 lbs")
        #expect(LiveActivityRestContent(leftRunning: state) == turned)
    }

    /// A Set logged from the card reads back on the island, which reads `dictation`, while the card
    /// stays on the next Set's face.
    @Test func aReadbackForTheIslandAloneLeavesTheCardItsFace() {
        let logged = LiveActivityDictation.logged(
            "1002.5×5 @7",
            to: LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 1, setsTotal: 3)
        )

        let islandOnly = WorkoutActivityAttributes.ContentState(
            restContent: Self.squatRest,
            dictation: logged,
            readbackStaysOffTheCard: true
        )
        let spoken = WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, dictation: logged)

        #expect(islandOnly.dictation == logged)
        #expect(islandOnly.cardReadback == nil)
        #expect(spoken.cardReadback == logged, "a Dictation's readback still takes the card")
    }

    /// An activity left running across an update holds content the build before wrote, with no
    /// Card Face and no numbers. Content that fails to decode freezes the card on what it drew.
    @Test func contentTheBuildBeforeWroteDecodesOntoTheRestFace() throws {
        let trunk = """
            {
              "exerciseName": "Back Squat",
              "prescribedReps": "5",
              "prescribedLoad": "RPE7",
              "weightValue": "235",
              "weightUnit": "lbs",
              "setsDone": 1,
              "setsTotal": 3,
              "variant": "restTimerSetsLeft",
              "appearance": "dark",
              "restStartDate": 800000000,
              "restEndDate": 800000120,
              "loggablePress": {
                "ready": {
                  "_0": {
                    "repChoices": [3, 4, 5, 6, 7],
                    "prescribedReps": [5],
                    "rpeChoices": ["6", "6.5", "7", "7.5", "8"],
                    "prescribedRPE": "7",
                    "setIdentity": "Set",
                    "chosenReps": 6
                  }
                }
              },
              "cadence": "3:1:1",
              "coachNote": "Brace hard",
              "pendingWrites": 0
            }
            """

        let state = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: Data(trunk.utf8))

        #expect(state.face == .rest)
        #expect(state.stats.isEmpty)
        #expect(state.cardReadback == nil)
        #expect(state.loggablePress == LoggablePress(.ready(Self.squatOffer)))
        #expect(LiveActivityRestContent(leftRunning: state)?.face == .rest)
    }

    private static let squatOffer = LockScreenOffer(
        repChoices: [3, 4, 5, 6, 7],
        prescribedReps: [5],
        rpeChoices: ["6", "6.5", "7", "7.5", "8"],
        prescribedRPE: "7",
        setIdentity: "Set"
    )

    private static var squatRest: LiveActivityRestContent {
        LiveActivityRestContent(
            exerciseName: "Back Squat",
            prescribedReps: "5",
            prescribedLoad: "RPE7",
            weightValue: "1002.5",
            weightUnit: "lbs",
            setsDone: 1,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090),
            press: .ready(squatOffer),
            stats: LockScreenStat.row(
                weight: .pounds(1002.5),
                prescription: Prescription(reps: "5", load: "RPE7", percentOneRM: nil),
                repsCell: "5"
            ),
            cadence: "3:1:1",
            coachNote: "Brace hard",
            start: nil
        )
    }
}

@MainActor
private final class PressSpy: LockScreenPressPerforming {
    private(set) var presses: [String] = []

    func turnCard(to face: LockScreenCardFace, pressing setIdentity: String?) async {
        presses.append(["turn", face.token, setIdentity].compactMap { $0 }.joined(separator: " "))
    }

    func logSet(setIdentity: String, reps: Int, rpe: String) async {
        presses.append("log \(setIdentity) \(reps) \(rpe)")
    }
}

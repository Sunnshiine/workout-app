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
            readbackStaysOffTheCard: true,
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
            cardTurn: nil,
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
            readbackStaysOffTheCard: nil,
            loggablePress: .needsApp,
            cardFace: .rest,
            cardTurn: nil,
            cardStats: [],
            cadence: nil,
            coachNote: nil,
            start: nil,
            pendingWrites: 0
        )

        #expect(state.weightText == expected)
    }

    @Test func eachControlHandsItsTapToTheApp() async throws {
        let spy = PressSpy()
        let registered = LockScreenPresses.performer
        LockScreenPresses.performer = spy
        defer { LockScreenPresses.performer = registered }

        _ = try await TurnLockScreenCardIntent(to: .coachNote, pressing: nil).perform()
        _ = try await TurnLockScreenCardIntent(to: .rest, pressing: nil).perform()
        _ = try await TurnLockScreenCardIntent(to: .reps, pressing: "Set").perform()
        _ = try await TurnLockScreenCardIntent(to: .rpe(reps: 6), pressing: "Set").perform()
        _ = try await LogSetAtRPEIntent(setIdentity: "Set", reps: 6, rpe: "7.5").perform()

        #expect(spy.presses == ["turn coachNote", "turn rest", "turn reps Set", "turn rpe 6 Set", "log Set 6 7.5"])
    }

    /// A face this build cannot read fails rather than turning the card to its rest face.
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

    /// A press that relaunched the app reads the rest back off the running activity, which must
    /// still be on the face it showed.
    @Test func theActivityCarriesTheFaceAndTheNumbersBothWays() throws {
        let turned = Self.squatRest.turned(to: .rpe(reps: 6))

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

        let spoken = WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, dictation: logged)
        let islandOnly = WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, islandReading: logged)

        #expect(islandOnly.dictation == logged)
        #expect(islandOnly.cardReadback == nil)
        #expect(spoken.cardReadback == logged, "a Dictation's readback still takes the card")
    }

    /// The athlete can turn the card while the island reads a Set Log back. The turn redraws the
    /// card, and the island keeps its readback until the hold takes it off.
    @Test func aCardRedrawnUnderTheIslandsReadbackKeepsIt() {
        let logged = LiveActivityDictation.logged(
            "1002.5×5 @7",
            to: LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 1, setsTotal: 3)
        )
        let onReps = Self.squatRest.turned(to: .reps)

        let underTheIsland = WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, islandReading: logged).redrawn(as: onReps)
        let withNoReadback = WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, dictation: nil).redrawn(as: onReps)

        #expect(underTheIsland.face == .reps)
        #expect(underTheIsland.dictation == logged)
        #expect(underTheIsland.cardReadback == nil)
        #expect(withNoReadback == WorkoutActivityAttributes.ContentState(restContent: onReps, dictation: nil))
    }

    /// The widget draws a face arriving from the side the card turned, so the way rides the content.
    @Test func theActivityCarriesTheWayTheCardTurned() {
        let onRPE = Self.squatRest.turned(to: .reps).turned(to: .rpe(reps: 6))
        let backOnReps = onRPE.turned(to: .reps)

        #expect(WorkoutActivityAttributes.ContentState(restContent: Self.squatRest, dictation: nil).turn == .forward)
        #expect(WorkoutActivityAttributes.ContentState(restContent: onRPE, dictation: nil).turn == .forward)
        #expect(WorkoutActivityAttributes.ContentState(restContent: backOnReps, dictation: nil).turn == .back)
        #expect(WorkoutActivityAttributes.ContentState(restContent: backOnReps, islandReading: Self.loggedSquat).turn == .back)
    }

    /// No rest follows the Set, so the card holds what was logged over a whole fill, with no
    /// countdown and nothing to press, and the island alone reads it back.
    @Test func aSetLoggedWithNoRestToFollowHoldsItsNumbersWithNothingToPress() throws {
        let session = makeSingleSession(exercises: [Exercise(name: "Back Squat", coachNote: "Brace hard")])
        let exercise = try #require(session.exercises.first)
        let last = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE7", percentOneRM: nil, state: .logged)
        exercise.sets = [last]
        let position = try #require(SessionSetOrder.orderedSets(in: session).last)
        let loggedSet = LiveActivityLoggedSetContent(
            LiveActivitySetContent(position),
            holding: SetLog(weight: .pounds(1002.5), reps: 5, rpe: .seven)
        )

        let state = WorkoutActivityAttributes.ContentState(loggedSet: loggedSet, islandReading: Self.loggedSquat)

        #expect(state.exerciseName == "Back Squat")
        #expect(state.loggablePress == .settled)
        #expect(state.face == .rest)
        #expect(state.stats.map(\.value) == ["1,002.5", "5", "7"])
        #expect(state.restStartDate == nil)
        #expect(state.restEndDate == nil)
        #expect(state.lockScreenFill == .whole)
        #expect(state.coachNote == nil)
        #expect(state.start == nil)
        #expect(state.dictation == Self.loggedSquat)
        #expect(state.cardReadback == nil, "nothing on the card reads Logged")
        #expect(LiveActivityRestContent(leftRunning: state) == nil, "a press that relaunched the app finds no rest to ride")
    }

    private static let loggedSquat = LiveActivityDictation.logged(
        "1002.5×5 @7",
        to: LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 1, setsTotal: 3)
    )

    /// An activity left running across an update holds content the build before wrote, with no
    /// Card Face and no numbers. Content that fails to decode freezes the card on what it drew.
    @Test func contentTheBuildBeforeWroteDecodesOntoTheRestFace() throws {
        let earlierBuild = """
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

        let state = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: Data(earlierBuild.utf8))

        #expect(state.face == .rest)
        #expect(state.turn == .forward)
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

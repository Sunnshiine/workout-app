import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

#if os(iOS)
    @MainActor
    @Test func productionContentStateSaysHowManySetsAreLeft() {
        let restContent = LiveActivityRestContent(
            exerciseName: "Bench Press",
            prescribedReps: "5",
            prescribedLoad: "RPE 8",
            weightValue: "",
            weightUnit: "lbs",
            setsDone: 1,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )

        let state = WorkoutActivityAttributes.ContentState(restContent: restContent)

        #expect(state.restContextText == "2 sets left")
    }

    @MainActor
    @Test(arguments: [
        ("1", "1 rep"),
        ("5", "5 reps"),
        ("10", "10 reps"),
        ("3-5", "3-5 reps"),
        ("AMRAP", "AMRAP"),
        ("", "")
    ])
    func liveActivityPrescribedRepsTextSaysRepForASingle(prescribedReps: String, expected: String) {
        let state = restContentState(prescribedReps: prescribedReps, prescribedLoad: "RPE 8")

        #expect(state.prescribedRepsText == expected)
    }

    @MainActor
    @Test func liveActivityPrescriptionTextSaysRepForASingle() {
        let state = restContentState(prescribedReps: "1", prescribedLoad: "405 lb")

        #expect(state.prescriptionText == "1 rep / 405 lb")
    }

    @MainActor
    private func restContentState(
        prescribedReps: String,
        prescribedLoad: String
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            restContent: LiveActivityRestContent(
                exerciseName: "Back Squat",
                prescribedReps: prescribedReps,
                prescribedLoad: prescribedLoad,
                weightValue: "",
                weightUnit: "lbs",
                setsDone: 1,
                setsTotal: 3,
                variant: .restTimerSetsLeft,
                restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
                restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
            )
        )
    }
#endif

@MainActor
@Test func liveActivityCreationPolicyAllowsOnlySuccessfulUserSetLogInCurrentSession() {
    let allowedEvent = LiveActivityProductionEvent(
        source: .userSetLog,
        outcome: .success,
        sessionScope: .currentSession
    )

    #expect(LiveActivityCreationPolicy.shouldCreateOrUpdate(for: allowedEvent))

    let refusedEvents =
        LiveActivityProductionEvent.Source.allCases
        .filter { $0 != .userSetLog }
        .map {
            LiveActivityProductionEvent(source: $0, outcome: .success, sessionScope: .currentSession)
        }
        + [
            LiveActivityProductionEvent(source: .userSetLog, outcome: .failure, sessionScope: .currentSession),
            LiveActivityProductionEvent(source: .userSetLog, outcome: .success, sessionScope: .nonCurrentSession)
        ]

    for event in refusedEvents {
        #expect(!LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event))
    }
}

@Test func liveActivityReadyStateStartsAtRestDeadline() {
    let restEndDate = Date(timeIntervalSinceReferenceDate: 1_090)
    let content = LiveActivityRestContent(
        exerciseName: "Bench Press",
        prescribedReps: "5",
        prescribedLoad: "RPE 8",
        weightValue: "",
        weightUnit: "lbs",
        setsDone: 1,
        setsTotal: 3,
        variant: .restTimerSetsLeft,
        restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
        restEndDate: restEndDate
    )

    #expect(!LiveActivityInvalidationPolicy.isReady(content, at: restEndDate.addingTimeInterval(-1)))
    #expect(LiveActivityInvalidationPolicy.isReady(content, at: restEndDate))
    #expect(content.setsLeftText == "2 sets left")
}

@Test func liveActivityReadyReminderExpiresAtThirtyMinuteCap() {
    let restEndDate = Date(timeIntervalSinceReferenceDate: 1_090)
    let content = LiveActivityRestContent(
        exerciseName: "Bench Press",
        prescribedReps: "5",
        prescribedLoad: "RPE 8",
        weightValue: "",
        weightUnit: "lbs",
        setsDone: 1,
        setsTotal: 3,
        variant: .restTimerSetsLeft,
        restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
        restEndDate: restEndDate
    )
    let capDate = restEndDate.addingTimeInterval(30 * 60)

    #expect(LiveActivityInvalidationPolicy.postRestCapEndDate(for: content) == capDate)
    #expect(!LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: content, at: capDate.addingTimeInterval(-1)))
    #expect(LiveActivityInvalidationPolicy.shouldEndReadyReminder(for: content, at: capDate))
}

/// A Detached Session has no Session Coordinate, so its rest names no target and the next
/// reconcile ends it rather than matching some other Session by Day.
@MainActor
@Test func liveActivityContentForADetachedSessionHasNoTarget() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = [exercise]
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.target == nil)
    #expect(content.exerciseName == "Bench Press")
}

@MainActor
@Test func liveActivityContentFallsBackToOpenExerciseInCurrentWeek() throws {
    let openExercise = makeExercise(name: "DB Row", order: 0, setStates: [.pending])
    let openSession = makeSingleSession(dayNumber: 1, exercises: [openExercise])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([openSession, currentSession])
    let loggedSet = try #require(currentExercise.sets.first)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "DB Row")
    #expect(content.setsLeftText == "1 set left")
    #expect(content.target?.session == SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)))
}

@MainActor
@Test func openExerciseFallbackAndMakeupQueueSelectTheSameFirstPendingSet() throws {
    // Two Open Exercises in an earlier Day; the fallback and the makeup queue
    // read the same navigation-module query, so both must land on the first
    // Open Exercise ("DB Row") and its first Pending Set.
    let dbRow = makeExercise(name: "DB Row", order: 0, setStates: [.logged, .pending])
    let curl = makeExercise(name: "Curl", order: 1, setStates: [.pending])
    let openSession = makeSingleSession(dayNumber: 1, exercises: [dbRow, curl])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([openSession, currentSession])
    let loggedSet = try #require(currentExercise.sets.first)

    let makeupQueue = SessionProgressTracker().openExercises(for: currentSession)
    let firstOpen = try #require(makeupQueue.first)
    let orderedSets = firstOpen.exercise.sets.sorted { $0.index < $1.index }
    let firstPending = try #require(orderedSets.first { $0.isPending })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(makeupQueue.map(\.exercise.exerciseName.entered) == ["DB Row", "Curl"])
    #expect(content.exerciseName == firstOpen.exercise.exerciseName.base)
    #expect(
        content.target?.setID
            == ActiveSetID(exerciseOrder: firstOpen.exercise.order, setIndex: firstPending.index)
    )
}

@MainActor
@Test func liveActivityOpenExerciseFallbackPicksEarliestEarlierDayFirstPendingSet() throws {
    // Two earlier Current-Week days each hold Pending Sets. Routing the makeup
    // fallback through the Open Exercise owner must still land on the *earliest*
    // earlier day, and within it the first Pending Set (skipping a leading
    // fully-logged Exercise).
    let day1Logged = makeExercise(name: "Warmup", order: 0, setStates: [.logged])
    let day1Open = makeExercise(name: "DB Row", order: 1, setStates: [.logged, .pending])
    let day1 = makeSingleSession(dayNumber: 1, exercises: [day1Logged, day1Open])
    let day2Open = makeExercise(name: "Chin Up", order: 0, setStates: [.pending])
    let day2 = makeSingleSession(dayNumber: 2, exercises: [day2Open])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([day1, day2, currentSession])
    let loggedSet = try #require(currentExercise.sets.first)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "DB Row")
    #expect(content.target?.session == SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)))
    #expect(content.target?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
}

@MainActor
@Test func widgetUpNextAndOnScreenFocusLegitimatelyDivergeOnOpenExerciseFallback() throws {
    // The widget's up-next carries the Open-Exercise makeup fallback; the focus
    // engine deliberately does not. With the Current Session fully settled but an
    // earlier Current-Week day still Open, the two policies legitimately point at
    // different Sets — the widget at the earlier day's Pending Set, the focus at
    // nothing. Pinning this keeps a future refactor from silently unifying them.
    let openExercise = makeExercise(name: "DB Row", order: 0, setStates: [.pending])
    let openSession = makeSingleSession(dayNumber: 1, exercises: [openExercise])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.pending])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([openSession, currentSession])
    let logging = try #require(currentExercise.sets.first)

    let focus = ActiveSetFocusManager(session: currentSession)
    logging.state = .logged
    focus.advanceAfterLog(logging, in: currentSession)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: logging,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    // Widget up-next: the earlier day's Open Exercise.
    #expect(content.exerciseName == "DB Row")
    #expect(content.target?.session == SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)))
    // On-screen focus: nothing left in the Current Session, and no fallback.
    #expect(focus.activeSetID == nil)
    // The two scopes disagree, by design.
    #expect(content.target?.setID != focus.activeSetID)
}

@MainActor
@Test func liveActivityTargetValidationKeepsOpenExerciseTargetFromCurrentWeek() throws {
    let openExercise = makeExercise(name: "DB Row", order: 0, setStates: [.pending])
    let openSession = makeSingleSession(dayNumber: 1, exercises: [openExercise])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([openSession, currentSession])
    let loggedSet = try #require(currentExercise.sets.first)
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(!LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: currentSession)))

    openExercise.sets[0].state = .skipped

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: currentSession)))
}

@MainActor
@Test func liveActivityTargetValidationEndsWhenCurrentOrViewedSessionChanges() throws {
    let first = makeSingleSession(
        dayNumber: 1,
        exercises: [
            makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
        ]
    )
    let second = makeSingleSession(
        dayNumber: 2,
        exercises: [
            makeExercise(name: "Bench Press", order: 0, setStates: [.pending])
        ]
    )
    connectCurrentWeek([first, second])
    let loggedSet = try #require(first.exercises.first?.sets.first { $0.index == 0 })
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: first,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: first, currentSession: second)))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: second, currentSession: first)))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: nil, currentSession: first)))
}

@MainActor
func makeSingleSession(dayNumber: Int = 1, exercises: [Exercise]) -> Session {
    let session = Session(dayNumber: dayNumber, date: nil)
    session.exercises = exercises
    connectCurrentWeek([session])
    return session
}

@MainActor
private func connectCurrentWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
    week.block = Block(tabName: "Block 27")
}

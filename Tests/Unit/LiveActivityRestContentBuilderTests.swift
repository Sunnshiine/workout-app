import Foundation
import Testing

@testable import WorkoutTracker

#if os(iOS)
    @MainActor
    @Test func liveActivityLabDefaultsToAcceptedRestSetsLeftVariant() {
        #expect(LiveActivityLabDefaults.defaultVariant == .restTimerSetsLeft)
        #expect(LiveActivityLabDefaults.productionVariantTitle == "Rest + Sets Left")
    }

    @MainActor
    @Test func liveActivityLabRetainsAllPrototypeVariants() {
        #expect(LiveActivityLabDefaults.prototypeVariants == DesignVariant.allCases)
    }

    @MainActor
    @Test func productionContentStateUsesAcceptedRestSetsLeftVariant() {
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

        #expect(state.variant == .restTimerSetsLeft)
        #expect(state.restContextText == "2 sets left")
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

@Test func liveActivityReadyStateStartsAtRestDeadlineAndKeepsSetContext() {
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
    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedReps == "5")
    #expect(content.prescribedLoad == "RPE 8")
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

@MainActor
@Test func liveActivityInvalidationPolicyEndsForSheetAndAuthEventsButNotAmbientEvents() {
    #expect(LiveActivityInvalidationPolicy.shouldEnd(for: .moveOn))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(for: .sheetSwitch))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(for: .signOut))
    #expect(!LiveActivityInvalidationPolicy.shouldEnd(for: .restExpired))
    #expect(!LiveActivityInvalidationPolicy.shouldEnd(for: .appBackgrounded))
    #expect(!LiveActivityInvalidationPolicy.shouldEnd(for: .syncStateChanged))
    #expect(!LiveActivityInvalidationPolicy.shouldEnd(for: .settingsOpened))
    #expect(!LiveActivityInvalidationPolicy.shouldEnd(for: .developerToolsOpened))
}

@MainActor
@Test func liveActivityContentTargetsNextPendingSetInSameExerciseAndCountsDisplayedExercisePendingSets() throws {
    let startDate = Date(timeIntervalSinceReferenceDate: 1_000)
    let endDate = Date(timeIntervalSinceReferenceDate: 1_090)
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: startDate,
            restEndDate: endDate
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedReps == "5")
    #expect(content.prescribedLoad == "RPE 8")
    #expect(content.setsDone == 1)
    #expect(content.setsTotal == 3)
    #expect(content.setsLeft == 2)
    #expect(content.setsLeftText == "2 sets left")
    #expect(content.variant == .restTimerSetsLeft)
    #expect(content.restStartDate == startDate)
    #expect(content.restEndDate == endDate)
    #expect(content.target?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(content.target?.session == LiveActivitySessionIdentity(blockTab: nil, weekNumber: 1, dayNumber: 1))
}

@MainActor
@Test func liveActivityContentTargetsNextExercisesFirstPendingSet() throws {
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .pending])
    let session = makeSingleSession(exercises: [squat, bench])
    let loggedSet = try #require(squat.sets.first)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedLoad == "RPE 7")
    #expect(content.setsLeftText == "2 sets left")
}

@MainActor
@Test func liveActivityInSessionUpNextMatchesSessionSetOrderOwnerAcrossStateMix() throws {
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged, .skipped, .pending])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .logged])
    let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
    let session = makeSingleSession(exercises: [squat, bench, row])
    let loggedSet = try #require(squat.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    let ownerTarget = try #require(SessionSetOrder.nextPendingSet(after: loggedSet, in: session))
    #expect(content.target?.setID == ownerTarget.setID)
    #expect(content.target?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 2))
    #expect(content.exerciseName == "Back Squat")
}

@MainActor
@Test func liveActivityContentUsesSupersetAlternationAndCountsDisplayedExerciseOnly() throws {
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged, .pending])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .pending, .pending])
    let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
    let session = makeSingleSession(exercises: [squat, bench, row])
    let loggedSet = try #require(squat.sets.first { $0.index == 0 })
    let supersetState = SupersetState()
    #expect(supersetState.createSuperset(with: [squat, bench], in: session))

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            supersetState: supersetState,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedLoad == "RPE 7")
    #expect(content.setsDone == 0)
    #expect(content.setsTotal == 3)
    #expect(content.setsLeftText == "3 sets left")
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
    #expect(content.target?.session == LiveActivitySessionIdentity(blockTab: nil, weekNumber: 1, dayNumber: 1))
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
    #expect(content.target?.session == LiveActivitySessionIdentity(blockTab: nil, weekNumber: 1, dayNumber: 1))
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
    #expect(content.target?.session == LiveActivitySessionIdentity(blockTab: nil, weekNumber: 1, dayNumber: 1))
    // On-screen focus: nothing left in the Current Session, and no fallback.
    #expect(focus.activeSetID == nil)
    // The two scopes disagree, by design.
    #expect(content.target?.setID != focus.activeSetID)
}

@MainActor
@Test func liveActivityContentSuppressesWhenNoPendingTargetExists() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first)

    let content = LiveActivityRestContentBuilder.content(
        afterLogging: loggedSet,
        in: session,
        restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
        restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
    )

    #expect(content == nil)
}

@MainActor
@Test func liveActivityTargetValidationKeepsMatchingCurrentDisplayedPendingSet() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(
        LiveActivityInvalidationPolicy.shouldEnd(
            content,
            displayedSession: session,
            currentSession: session
        ) == false
    )
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

    #expect(
        !LiveActivityInvalidationPolicy.shouldEnd(
            content,
            displayedSession: currentSession,
            currentSession: currentSession
        )
    )

    openExercise.sets[0].state = .skipped

    #expect(
        LiveActivityInvalidationPolicy.shouldEnd(
            content,
            displayedSession: currentSession,
            currentSession: currentSession
        )
    )
}

@MainActor
@Test func liveActivityTargetValidationEndsWhenCurrentOrDisplayedSessionChanges() throws {
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

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, displayedSession: first, currentSession: second))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, displayedSession: second, currentSession: first))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, displayedSession: nil, currentSession: first))
}

@MainActor
@Test func liveActivityTargetValidationEndsWhenTargetSetIsNoLongerPending() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })
    let targetSet = try #require(exercise.sets.first { $0.index == 1 })
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    targetSet.state = .logged

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, displayedSession: session, currentSession: session))
}

@MainActor
private func makeSingleSession(dayNumber: Int = 1, exercises: [Exercise]) -> Session {
    let session = Session(dayNumber: dayNumber, date: nil)
    session.exercises = exercises
    connectCurrentWeek([session])
    return session
}

@MainActor
private func connectCurrentWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
}

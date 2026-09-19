import Foundation
import SwiftData
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
@Test func liveActivityUpNextSkipsSettledSetsToTheNextPendingSetInOrder() throws {
    // The rest widget's "up next" walks past the just-Logged Set and a following
    // Skipped Set to the next Pending Set — the third Back Squat Set — rather
    // than jumping to the later Exercises that also hold Pending Sets.
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

    #expect(makeupQueue.map(\.exercise.name) == ["DB Row", "Curl"])
    #expect(content.exerciseName == firstOpen.exercise.name)
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

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: session)) == false)
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

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: first, currentSession: second)))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: second, currentSession: first)))
    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .resolve(viewedSession: nil, currentSession: first)))
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

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: session)))
}

@MainActor
@Test func liveActivityTargetValidationKeepsRestWhenASecondInstanceBacksTheSameSession() throws {
    let container = try makeStoredWeek()
    defer { withExtendedLifetime(container) {} }
    let viewed = try #require(try storedWeekSession(dayNumber: 1, in: container.mainContext))
    let loggedSet = try #require(viewed.exercises.first?.sets.first { $0.index == 0 })
    loggedSet.state = .logged
    try container.mainContext.save()
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: viewed,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    let secondInstance = try #require(try storedWeekSession(dayNumber: 1, in: ModelContext(container)))
    #expect(secondInstance !== viewed)
    #expect(secondInstance.persistentModelID == viewed.persistentModelID)

    #expect(
        LiveActivityInvalidationPolicy.shouldEnd(
            content,
            at: .resolve(viewedSession: viewed, currentSession: secondInstance)
        ) == false
    )
}

@MainActor
@Test func liveActivityRestSurvivesAStoreReloadAtTheLiveEdge() throws {
    let container = try makeStoredWeek()
    defer { withExtendedLifetime(container) {} }
    let store = WorkoutStore(
        context: container.mainContext,
        defaults: try #require(UserDefaults(suiteName: "live-edge.\(UUID())"))
    )
    store.reload()

    let viewed = try #require(store.displayedSession)
    let loggedSet = try #require(viewed.exercises.first?.sets.first { $0.index == 0 })
    loggedSet.state = .logged
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: viewed,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    store.reload()

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: store.liveEdge) == false)
}

@MainActor
private func storedWeekSession(dayNumber: Int, in context: ModelContext) throws -> Session? {
    let block = try context.fetch(FetchDescriptor<Block>()).first
    return block?.weeks.first { $0.number == 1 }?.sessions.first { $0.dayNumber == dayNumber }
}

@MainActor
private func makeStoredWeek() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration("live-edge-\(UUID().uuidString)", isStoredInMemoryOnly: true)
    )
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: (1...2).map { day in
                    ParsedSession(
                        dayNumber: day,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: (0...1).map { index in
                                    ParsedSet(
                                        index: index,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil
                                    )
                                }
                            )
                        ]
                    )
                }
            )
        ]
    )
    container.mainContext.insert(BlockBuilder.makeBlock(from: parsed))
    try container.mainContext.save()
    return container
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

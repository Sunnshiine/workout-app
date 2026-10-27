import Foundation
import Testing

@testable import WorkoutTracker

// Presses and taps across a real `app.sync()`, which deletes the cached Block and inserts the one
// it parsed, so every Set the stage read before it is detached.

private typealias StoreStage = (
    app: WorkoutApplication, coordinator: SessionCoordinator, sync: SpySessionSyncAdapter, sheet: LocalWorkbookSheetsClient
)

/// The real stores over the fresh-block workbook, with the coordinator on the Viewed Session as
/// the Session screen shows it. The sync adapter is a spy, so a refused write is visible and
/// nothing flushes until the test does. `sheet` stands in for the coach editing the Sheet.
@MainActor
private func makeStoreStage(dictation: SetDictation? = nil) async throws -> StoreStage {
    let sheet = LocalWorkbookSheetsClient(workbook: WorkbookScenario.freshBlock.workbook())
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { Date(timeIntervalSince1970: 1_780_000_000) }))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(
        wiring: .fixture(logging: app.workout, navigation: app.workout, sync: sync),
        dictation: dictation
    )
    coordinator.view(try #require(app.workout.viewedSession))
    return (app, coordinator, sync, sheet)
}

@MainActor
private func makeStorePress(saying heard: String) async throws -> (StoreStage, pressed: ExerciseSet) {
    let stage = try await makeStoreStage(dictation: SetDictation(transcriber: CannedSetTranscriber(candidates: [heard])))
    let pressed = try card(stage.coordinator, in: try #require(stage.app.workout.viewedSession)).set
    try #require(pressed.exercise?.exerciseName.entered == "Back Squat" && pressed.exercise?.order == 0 && pressed.index == 0)
    stage.coordinator.startDictation(for: pressed)
    return (stage, pressed)
}

/// Every Set of the Session the stage shows that holds a Set Log.
@MainActor
private func loggedSets(in session: Session) -> [ExerciseSet] {
    session.exercises.flatMap(\.sets).filter { $0.setLog != nil }
}

/// The store refuses a write for a Set no Block holds (#1052), and the stage finds the Session
/// again by its coordinate, so the card it builds next writes the parsed Set.
@MainActor
@Test func aTapOnACardASyncReplacedIsRefusedAndTheCardBuiltAfterItWritesTheParsedSet() async throws {
    let (app, coordinator, sync, _) = try await makeStoreStage()
    let before = try #require(app.workout.viewedSession)
    let staleCard = try #require(exerciseStage(coordinator, in: before)?.card)
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)

    _ = try await app.sync()
    coordinator.log(log, for: staleCard)

    #expect(sync.reportedErrors.count == 1)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)

    let parsed = try #require(app.workout.viewedSession)
    #expect(parsed !== before)
    let card = try #require(exerciseStage(coordinator, in: parsed)?.card)
    coordinator.log(log, for: card)

    #expect(sync.reportedErrors.count == 1)
    #expect(card.set.setLog == log)
    let flush = try await app.flush()
    #expect(flush.written == flush.attempted && flush.written > 0)
    #expect(flush.conflictedWrites.isEmpty)
}

/// A sync detaches the Set a press began on, and the order SwiftData ran the cascade delete in
/// (#1036) decides whether that Set still reads its coordinates. A release on it then writes
/// nothing, or logs the parsed Set at the same coordinates, which is the same Set in the Sheet.
/// Either way the Detached Set takes nothing, no other Set takes the write, and the press ends.
@MainActor
@Test func aPressReleasedOnItsDetachedSetWritesAtMostTheParsedSetAtItsCoordinates() async throws {
    let ((app, coordinator, sync, _), pressed) = try await makeStorePress(saying: "185 for 6 at 7")
    let pressedID = try SetCoordinates(of: pressed).id

    _ = try await app.sync()
    let parsed = try #require(app.workout.viewedSession)
    coordinator.view(parsed)
    let outcome = await coordinator.finishDictation(of: pressed)

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == nil || outcome == .logged(logged, heard: "185 for 6 at 7"))
    #expect(coordinator.dictation?.state == .idle)
    #expect(pressed.setLog == nil)
    #expect(sync.reportedErrors.isEmpty)
    let writes = try app.sync.fetchPendingWriteRecords().map(SetCoordinates.ID.init)
    #expect(writes == (outcome == nil ? [] : [pressedID]))
    let written = try loggedSets(in: parsed).map { try SetCoordinates(of: $0).id }
    #expect(written == (outcome == nil ? [] : [pressedID]))
    #expect(loggedSets(in: parsed).allSatisfy { $0.setLog == logged })
}

/// The card the stage builds after a sync shows the parsed Set the press began on, so a release
/// there logs it, and the log flushes to the Sheet.
@MainActor
@Test func aPressReleasedOnTheCardBuiltAfterASyncLogsTheParsedSet() async throws {
    let ((app, coordinator, sync, _), _) = try await makeStorePress(saying: "185 for 6 at 7")

    _ = try await app.sync()
    let parsed = try #require(app.workout.viewedSession)
    coordinator.view(parsed)
    let released = try card(coordinator, in: parsed).set
    let outcome = await coordinator.finishDictation(of: released)

    let logged = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    #expect(outcome == .logged(logged, heard: "185 for 6 at 7"))
    #expect(released.setLog == logged)
    #expect(coordinator.dictation?.state == .idle)
    #expect(loggedSets(in: parsed).map(ObjectIdentifier.init) == [ObjectIdentifier(released)])
    #expect(sync.reportedErrors.isEmpty)
    let flush = try await app.flush()
    #expect(flush.written == 1 && flush.attempted == 1)
    #expect(flush.conflictedWrites.isEmpty)
}

/// Where a press is released after a sync on the real stores.
enum ReleaseAfterAReorder: CaseIterable {
    /// The Set the press began on, which the sync detached.
    case onThePressedSet
    /// The card the stage builds after the sync, on the Set now in the pressed Set's place.
    case onTheCardInItsPlace
}

/// The coach moved the RDL above Back Squat while a press on Back Squat's Set 1 ran, so the
/// parsed Set in the pressed Set's place is the RDL's. Wherever the press is released, and in
/// whichever order SwiftData ran the cascade delete (#1036), no Set takes what was said.
@MainActor
@Test(arguments: ReleaseAfterAReorder.allCases)
func aPressWhoseExerciseACoachMovedWritesNothingAfterTheSync(_ release: ReleaseAfterAReorder) async throws {
    let ((app, coordinator, sync, sheet), pressed) = try await makeStorePress(saying: "185 for 6 at 7")
    try await sheet.write(
        [
            "C15": "2-3:1:0 BB RDL", "D15": "2", "F15": "8", "H15": "RPE8",
            "C19": "Back Squat", "D19": "3", "F19": "5", "H19": "RPE7", "K19": ""
        ].map { SheetCellWrite(tabName: "Block 27", a1: $0.key, value: $0.value) },
        spreadsheetId: "FIXTURE"
    )

    _ = try await app.sync()
    let parsed = try #require(app.workout.viewedSession)
    let byOrder = parsed.exercises.sorted { $0.order < $1.order }.map(\.exerciseName.entered)
    try #require(byOrder.prefix(2) == ["2-3:1:0 BB RDL", "Back Squat"])
    coordinator.view(parsed)
    let released =
        switch release {
        case .onThePressedSet: pressed
        case .onTheCardInItsPlace: try card(coordinator, in: parsed).set
        }
    if release == .onTheCardInItsPlace {
        try #require(released.exercise?.order == 0 && released.index == 0)
    }
    let outcome = await coordinator.finishDictation(of: released)

    #expect(outcome == nil)
    #expect(coordinator.dictation?.state == .idle)
    #expect(pressed.setLog == nil)
    #expect(loggedSets(in: parsed).isEmpty)
    #expect(sync.reportedErrors.isEmpty)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

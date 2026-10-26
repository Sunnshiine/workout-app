import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)
private let window = SetDictation.silenceWindow

@MainActor
struct BackgroundDictationHarness {
    let app: WorkoutApplication
    let dictation: SetDictation
    let clock = ManualListeningClock()
    let liveActivity = SpyDictationLiveActivity()
    let signIn = FakeSignIn()
    /// The process's focus, which a stage binds when a test puts one up.
    let focus = ActiveSetFocusManager(session: nil)
    /// The process's one rest, which the stage's pill, the Live Activity, and the rest-end
    /// notification all read.
    let restTimer: RestTimer
    let restNotifications = RecordingRestNotificationScheduler()
    let restExpiry = MockRestExpiryScheduler()
    let background: BackgroundDictation

    init(hearing candidates: [String], selectingSpreadsheet: Bool = true, sheet: HeldWriteSheetsClient? = nil) async throws {
        try await self.init(
            transcriber: CannedSetTranscriber(candidates: candidates),
            selectingSpreadsheet: selectingSpreadsheet,
            sheet: sheet
        )
    }

    init(transcriber: any SetTranscriber, selectingSpreadsheet: Bool = true, sheet: HeldWriteSheetsClient? = nil) async throws {
        app = try WorkoutApplication(
            environment: AppEnvironment(
                storage: .inMemory,
                dictationRecords: .inMemory,
                sheetsClient: sheet ?? HeldWriteSheetsClient(holding: false),
                defaults: .inMemory(),
                now: { frozenNow }
            )
        )
        if selectingSpreadsheet {
            _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
        }
        dictation = SetDictation(
            transcriber: transcriber,
            reader: CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent))),
            journal: app.dictationJournal,
            clock: clock
        )
        restTimer = RestTimer(clock: ManualRestClock(now: frozenNow), notificationScheduler: restNotifications, expiryScheduler: restExpiry)
        background = BackgroundDictation(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            signIn: signIn,
            clock: clock
        )
    }

    /// Runs with a transcriber that hears everything at once, so listening ends a silence window on.
    func runUntilQuiet() async -> BackgroundDictation.Outcome {
        let run = Task { await background.run() }
        await clock.waitUntilSleeping(until: clock.now + VoiceActivity.frameDuration, orRecord: "It never started listening")
        clock.advance(by: window)
        return await run.value
    }

    func written(_ exerciseName: String, order: Int, set ordinal: Int, of total: Int) throws -> LiveActivityDictationContent.WrittenSet {
        let session = try #require(app.workout.currentSession)
        let setID = ActiveSetID(exerciseOrder: order, setIndex: ordinal - 1)
        return LiveActivityDictationContent.WrittenSet(
            exerciseName: exerciseName,
            setOrdinal: ordinal,
            setsTotal: total,
            target: session.placement.coordinate.map { LiveActivityRestTarget(session: $0, setID: setID) }
        )
    }

    func squat(set ordinal: Int) throws -> LiveActivityDictationContent.WrittenSet {
        try written("Back Squat", order: 0, set: ordinal, of: 3)
    }

    /// A Session screen up behind the intent, its stage on `session`, as with the app backgrounded.
    func stage(on session: Session) -> SessionCoordinator {
        let stage = SessionCoordinator(
            wiring: .fixture(logging: app.workout, restTimer: restTimer),
            dictation: dictation,
            focus: focus
        )
        stage.view(session)
        return stage
    }

    func expectNothingWritten(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try app.session(nil).exercises[0].sets[0].state == "pending", sourceLocation: sourceLocation)
        #expect(try app.sync.fetchPendingWriteRecords().isEmpty, sourceLocation: sourceLocation)
        #expect(signIn.restores == 0, "nothing to flush", sourceLocation: sourceLocation)
    }
}

@MainActor
final class SpyDictationLiveActivity: DictationLiveActivityAdapter {
    private(set) var shown: [(content: LiveActivityDictationContent, sessionLabel: String)] = []

    var readbacks: [LiveActivityDictationContent.Readback] { shown.map(\.content.readback) }
    var subjects: [LiveActivityDictationContent.Subject] { shown.map(\.content.subject) }
    var sessionLabels: [String] { shown.map(\.sessionLabel) }
    private(set) var noSets: [LiveActivityNoSetReadback] = []
    private(set) var withdrawals = 0
    /// Runs as a readback shows, as the app can come forward while the system draws it.
    var whileShowing: (LiveActivityDictationContent.Readback) -> Void = { _ in }
    /// Whether a Live Activity shows what is asked of it; false with Live Activities off.
    var isUp = true

    /// What the Live Activity reads once the run is over; nil when nothing is left on it.
    var finalReadback: LiveActivityDictationContent.Readback? {
        withdrawals > 0 ? nil : readbacks.last
    }

    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async -> Bool {
        shown.append((content, sessionLabel))
        whileShowing(content.readback)
        return isUp
    }

    func show(_ noSet: LiveActivityNoSetReadback) async -> Bool {
        noSets.append(noSet)
        return isUp
    }

    func withdrawReadback() async {
        withdrawals += 1
    }
}

@MainActor
final class FakeSignIn: SignInRestoring {
    private(set) var restores = 0

    func restorePreviousSignIn() async -> Bool {
        restores += 1
        return true
    }
}

@MainActor
final class HeldWriteSheetsClient: SheetsClient {
    private let workbook = LocalWorkbookSheetsClient(workbook: WorkbookScenario.freshBlock.workbook())
    private let held: HeldCall

    init(holding: Bool = true) {
        held = HeldCall(parks: holding ? 1 : 0)
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        try await workbook.listTabTitles(spreadsheetId: spreadsheetId)
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        try await workbook.listSpreadsheets(pageToken: pageToken)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        try await workbook.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        await held.hold()
        try await workbook.write(cells, spreadsheetId: spreadsheetId)
    }

    func waitUntilHeld(orRecord failure: Comment, sourceLocation: SourceLocation = #_sourceLocation) async {
        await held.waitUntilHeld(orRecord: failure, sourceLocation: sourceLocation)
    }

    /// Releases only a write already parked, so a test waits for one first.
    func release() {
        held.release()
    }
}

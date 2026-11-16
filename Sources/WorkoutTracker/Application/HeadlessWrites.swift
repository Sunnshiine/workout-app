import Foundation

/// What follows a write made with no stage on screen, whichever surface pressed: the rest the stage
/// would start, and a flush that restores the sign-in no scene did.
@MainActor
final class HeadlessWrites {
    /// How long the flush may hold the run after the result shows. A flush still going runs on,
    /// and a write that never lands stays queued for the next foreground (ADR-0006).
    nonisolated static let flushWait: Duration = .seconds(10)

    private let app: WorkoutApplication
    private let focus: ActiveSetFocusManager
    /// The process's one rest, which a write here starts as the stage would: its pill, the Live
    /// Activity, and the rest-end notification all read it.
    private let restTimer: RestTimer
    private let signIn: any SignInRestoring
    private let clock: any ListeningClock
    /// Held so the flush outlives `flushWait`; nil until a write asks for one.
    private(set) var flushing: Task<FlushReport?, Never>?

    init(
        app: WorkoutApplication,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        signIn: any SignInRestoring,
        clock: any ListeningClock
    ) {
        self.app = app
        self.focus = focus
        self.restTimer = restTimer
        self.signIn = signIn
        self.clock = clock
    }

    /// Set Logs the Sheet does not have yet. A readback counts them, so a Set still queued never
    /// reads as saved to the Sheet.
    var pendingWriteCount: Int {
        (try? app.sync.fetchPendingWriteRecords().count) ?? 0
    }

    /// Moves the card past this Set, starts the rest the stage would after it on the stage's own
    /// timer, and reads the rest back on the Set the card moved to. With no rest to start, the
    /// logged Set's Exercise as it now stands. Either counts the queue the write joined.
    func restSubject(
        afterLogging position: SessionSetPosition,
        in session: Session,
        wasSupersetMember: Bool
    ) -> LiveActivityDictationContent.Subject {
        let set = position.set
        focus.advanceAfterSpokenWrite(set, in: session, holding: false)
        guard
            let interval = restTimer.startRest(
                afterLogging: set,
                in: session,
                wasSupersetMember: wasSupersetMember,
                durations: app.settings
            ),
            var content = focus.liveActivityRestContent(
                in: session,
                history: app.lastPerformed.snapshot,
                restStartDate: interval.start,
                restEndDate: interval.end
            )
        else {
            var written = LiveActivitySetContent(position)
            written.pendingWrites = pendingWriteCount
            return .set(written)
        }
        content.pendingWrites = pendingWriteCount
        return .rest(content)
    }

    /// Restores the sign-in when no scene has, then flushes for at most `flushWait`.
    func flush() async {
        if !app.settings.isSignedIn, await signIn.restorePreviousSignIn() {
            app.settings.isSignedIn = true
        }
        let flushing = Task { @MainActor [app] in try? await app.flush() }
        self.flushing = flushing
        await BoundedWait.wait(for: flushing, until: clock.now + Self.flushWait, on: clock)
    }
}

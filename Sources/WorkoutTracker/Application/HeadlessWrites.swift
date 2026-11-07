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

    /// Starts the rest the stage would after this Set, on the stage's own timer, and reads it back
    /// toward the Set the card focuses next. With no rest to start, the logged Set's Exercise as it
    /// now stands.
    func restSubject(
        afterLogging position: SessionSetPosition,
        in session: Session,
        wasSupersetMember: Bool
    ) -> LiveActivityDictationContent.Subject {
        let set = position.set
        guard
            let interval = restTimer.startRest(
                afterLogging: set,
                in: session,
                wasSupersetMember: wasSupersetMember,
                durations: app.settings
            ),
            let content = focus.liveActivityRestContent(
                afterLogging: set,
                in: session,
                history: app.lastPerformed.snapshot,
                restStartDate: interval.start,
                restEndDate: interval.end
            )
        else { return .set(LiveActivitySetContent(position)) }
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

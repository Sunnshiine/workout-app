/// Runs the Lock Screen's presses in the app, on the same focus, rest, and Live Activity the stage
/// reads, whether or not a scene is on screen. One clock and one settle serve every press, so an
/// RPE press can tell how long ago the card turned.
@MainActor
final class LogSetAtRPEPerformer: LockScreenPressPerforming {
    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let restTimer: RestTimer
    private let liveActivity: LiveActivityProductionAdapter
    private let settle = RPEFaceSettle()
    private let clock = ContinuousListeningClock()

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: LiveActivityProductionAdapter
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.restTimer = restTimer
        self.liveActivity = liveActivity
    }

    func turnCard(to face: LockScreenCardFace, pressing setIdentity: String?) async {
        await press.turn(to: LockScreenFace(face), pressing: setIdentity)
    }

    func logSet(setIdentity: String, reps: Int, rpe: String) async {
        await press.logSet(setIdentity: setIdentity, reps: reps, rpe: rpe)
    }

    private var press: LockScreenPress {
        // A press that relaunched the app finds the rest this process did not start.
        liveActivity.takeOverRestLeftRunning()
        return LockScreenPress(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            settle: settle,
            signIn: GoogleSignInRestorer(),
            clock: clock
        )
    }
}

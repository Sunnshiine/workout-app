/// Runs `LogSetAtRPEIntent` in the app, on the same focus, rest, and Live Activity the stage reads,
/// whether or not a scene is on screen.
@MainActor
final class LogSetAtRPEPerformer: LogSetAtRPEPerforming {
    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let restTimer: RestTimer
    private let liveActivity: LiveActivityProductionAdapter

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

    func logSet(setIdentity: String, rpe: String) async {
        let press = RPEChipPress(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            signIn: GoogleSignInRestorer(),
            clock: ContinuousListeningClock()
        )
        await press.run(setIdentity: setIdentity, rpe: rpe)
    }
}

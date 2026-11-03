import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)

@Test(
    "A press that found the Speech Model not ready says what the athlete can do",
    arguments: [
        (SpeechModelState.absent, "Speech model downloads on Wi-Fi", "Speech model downloads on Wi-Fi. Unlock to log"),
        (.waitingForNetwork, "Speech model downloads on Wi-Fi", "Speech model downloads on Wi-Fi. Unlock to log"),
        (.downloading, "Speech model is still downloading", "Speech model still downloading. Unlock to log"),
        (.specializing, "Speech model is still preparing", "Speech model still preparing. Unlock to log"),
        (.failed(.download), "Speech model failed, reopen the app", "Speech model failed. Unlock to log"),
        (.failed(.load), "Speech model failed, reopen the app", "Speech model failed. Unlock to log"),
        (.loading, "Speech model was loading, say it again", "Speech model was loading, say it again"),
        (.downloaded, "Speech model was loading, say it again", "Speech model was loading, say it again"),
        (.unloaded(.idle), "Speech model was loading, say it again", "Speech model was loading, say it again")
    ] as [(SpeechModelState, String, String)]
)
func aPressThatFoundTheSpeechModelNotReadySaysWhatTheAthleteCanDo(state: SpeechModelState, card: String, lockScreen: String) {
    let rejection = SetDictation.Rejection.recording(.modelNotReady(state))
    let outcome = SetDictation.Outcome.rejected(rejection, heard: "")

    #expect(SetCardDictation(.finished(firstSet, outcome), for: firstSet) == .rejected(caption: card))
    #expect(BackgroundDictation.NotLogged.rejected(rejection, heard: "").caption == lockScreen)
}

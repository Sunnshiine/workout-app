import Testing

@testable import WorkoutTracker

@Test(
    "The Recording Transcript is the words heard, and a reading with none is no transcript",
    arguments: [
        (RecordingDecode.Result.heard("185 for 5 at 8.", segments: []), "185 for 5 at 8."),
        (.heard("", segments: []), nil),
        (.heard(" \n", segments: []), nil),
        (.missing(.modelNotReady(.absent)), nil),
        (.missing(.late), nil)
    ] as [(RecordingDecode.Result, String?)]
)
func theRecordingTranscriptIsTheWordsHeard(result: RecordingDecode.Result, transcript: String?) {
    #expect(RecordingDecode(result: result, timings: nil).transcript == transcript)
}

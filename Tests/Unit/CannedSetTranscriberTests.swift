import Testing

@testable import WorkoutTracker

@MainActor
@Test func theFixturesMicRecordsItsSamplesAsItGoesLive() async throws {
    let recorder = DictationRecorder()
    var heard: [String] = []

    try await CannedSetTranscriber(candidates: ["skip"], recording: [0.25, -0.5]).start(hearing: { heard.append($0) }, recording: recorder)

    #expect(recorder.close().samples == [0.25, -0.5])
    #expect(heard == ["skip"])
}

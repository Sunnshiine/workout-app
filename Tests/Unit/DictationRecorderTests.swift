import Testing

@testable import WorkoutTracker

private func append(_ samples: [Float], to recorder: DictationRecorder) {
    samples.withUnsafeBufferPointer(recorder.append)
}

@Test func aRecordingHoldsEveryAppendInOrderAndASnapshotLeavesItRecording() {
    let recorder = DictationRecorder()

    append([0.1, 0.2], to: recorder)
    let snapshot = recorder.snapshot()
    append([0.3], to: recorder)

    #expect(snapshot == DictationRecording(samples: [0.1, 0.2], isTruncated: false))
    #expect(recorder.close() == DictationRecording(samples: [0.1, 0.2, 0.3], isTruncated: false))
}

@Test func anAppendAfterCloseIsDroppedAndASecondCloseReturnsTheSameAudio() {
    let recorder = DictationRecorder()
    append([0.1], to: recorder)

    let closed = recorder.close()
    append([0.2], to: recorder)

    #expect(closed == DictationRecording(samples: [0.1], isTruncated: false))
    #expect(recorder.close() == closed)
}

@Test func audioPastThirtySecondsIsDroppedAndTheRecordingSaysSo() {
    let recorder = DictationRecorder()
    let capacity = 30 * DictationRecorder.sampleRate
    append([Float](repeating: 0.5, count: capacity - 1), to: recorder)

    append([0.6, 0.7], to: recorder)
    append([0.8], to: recorder)

    let recording = recorder.close()
    #expect(recording.samples.count == capacity)
    #expect(capacity == 480_000, "30 seconds at 16 kHz")
    #expect(recording.samples.last == 0.6)
    #expect(recording.isTruncated)
}

@Test func aRecordingFilledToCapacityExactlyIsNotTruncated() {
    let recorder = DictationRecorder()

    append([Float](repeating: 0.5, count: 30 * DictationRecorder.sampleRate), to: recorder)

    #expect(!recorder.close().isTruncated)
}

@Test func eachWholeFrameHasItsLevelThoughAnAppendSplitsIt() throws {
    let recorder = DictationRecorder()
    let frame = VoiceActivity.frameSamples

    append([Float](repeating: 0.5, count: 1000), to: recorder)
    append([Float](repeating: 0.5, count: frame - 1000) + [Float](repeating: 0.05, count: frame + 10), to: recorder)

    let levels = recorder.levels(from: 0)
    try #require(levels.count == 2, "the 10 samples of a third frame have no level yet")
    #expect(abs(levels[0] - -6.02) < 0.01, "half of full scale is 6 dB down")
    #expect(abs(levels[1] - -26.02) < 0.01)
    #expect(recorder.levels(from: 1) == [levels[1]])
    #expect(recorder.levels(from: 5) == [])
}

@Test func aSilentFrameIsFarBelowAnyRoom() throws {
    let recorder = DictationRecorder()

    append([Float](repeating: 0, count: VoiceActivity.frameSamples), to: recorder)

    #expect(try #require(recorder.levels(from: 0).first) < -150)
}

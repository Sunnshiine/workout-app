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
    #expect(recording.samples.last == 0.6)
    #expect(recording.isTruncated)
}

@Test func aRecordingFilledToCapacityExactlyIsNotTruncated() {
    let recorder = DictationRecorder()

    append([Float](repeating: 0.5, count: 30 * DictationRecorder.sampleRate), to: recorder)

    #expect(!recorder.close().isTruncated)
}

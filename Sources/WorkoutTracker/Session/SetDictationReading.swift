import os

extension SetDictation {
    /// A press's recording, or the recording so far, being read by the recording engine off the
    /// main actor. Nothing recorded is never read.
    @MainActor
    final class Reading {
        let recording: DictationRecording
        /// On the press's clock; nil when nothing was recorded to read.
        let askedAt: Duration?
        private var decoding: Task<RecordingDecode, Never>?
        private(set) var arrived: RecordingDecode?
        /// When the decode came in, on the press's clock.
        private(set) var readAt: Duration?
        /// When the decode was cancelled at the deadline.
        private(set) var droppedAt: Duration?

        init(of recording: DictationRecording, by reader: any RecordingTranscriber, on clock: any ListeningClock) {
            self.recording = recording
            askedAt = recording.samples.isEmpty ? nil : clock.now
            guard !recording.samples.isEmpty else { return }
            decoding = Task { @MainActor [weak self] in
                let decoding = SetDictation.signposter.beginInterval("RecordingDecode")
                let decode = await reader.transcribe(recording)
                SetDictation.signposter.endInterval("RecordingDecode", decoding)
                self?.arrived = decode
                self?.readAt = clock.now
                return decode
            }
        }

        /// The decode once it is in, or `late` at `deadline` on `clock`, which cancels the read. One
        /// already in decides whatever the clock says.
        func decode(by deadline: Duration, on clock: any ListeningClock) async -> RecordingDecode {
            guard let decoding else { return .missing(.nothingRecorded) }
            if let arrived { return arrived }
            guard let decode = await BoundedWait.wait(for: decoding, until: deadline, on: clock) else {
                decoding.cancel()
                droppedAt = clock.now
                return .missing(.late)
            }
            return decode
        }

        var isReading: Bool { decoding != nil && arrived == nil }

        /// In flight, or in with a transcript: a model that was not ready may be by the press's end.
        var isWorthKeeping: Bool {
            guard let arrived else { return decoding != nil }
            return arrived.transcript != nil
        }

        /// Returns once the decode is in, or at `deadline` on `clock`, leaving the read running.
        func arrival(until deadline: Duration, on clock: any ListeningClock) async {
            guard let decoding, arrived == nil else { return }
            await BoundedWait.wait(for: decoding, until: deadline, on: clock)
        }

        func cancel() {
            decoding?.cancel()
        }
    }
}

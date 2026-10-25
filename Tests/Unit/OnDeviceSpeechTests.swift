import CoreMedia
import Speech
import Testing

@testable import WorkoutTracker

@available(iOS 26, macOS 26, *)
private struct Phrase: TranscribedPhrase {
    let text: AttributedString
    let alternatives: [AttributedString]
    let range: CMTimeRange
    let resultsFinalizationTime: CMTime

    /// Seconds into the press. A tentative phrase is one the model has not finalized through its end.
    init(_ top: String, _ alternatives: String..., from start: Double, to end: Double, isFinal: Bool) {
        text = AttributedString(top)
        self.alternatives = alternatives.map { AttributedString($0) }
        range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000), end: CMTime(seconds: end, preferredTimescale: 1000))
        resultsFinalizationTime = isFinal ? range.end : range.start
    }
}

private let english = Locale(identifier: "en-US")

@available(iOS 26, macOS 26, *)
@Test func aDictationHearsThroughSpeechTranscriberWhereTheDeviceHasItAndDictationTranscriberElsewhere() {
    #expect(OnDeviceSpeech(transcriber: english, dictation: english) == .transcriber(english))
    #expect(OnDeviceSpeech(transcriber: nil, dictation: english) == .dictation(english))
    #expect(OnDeviceSpeech(transcriber: nil, dictation: nil) == nil)
}

// The Simulator has neither model, so only a Mac or a phone can build one to cancel.
#if !targetEnvironment(simulator)
    @available(iOS 26, macOS 26, *)
    @MainActor
    @Test func eachChoiceListensWithItsOwnModel() async {
        let transcribing = OnDeviceSpeech.transcriber(english).listening { _ in }
        let dictating = OnDeviceSpeech.dictation(english).listening { _ in }
        await transcribing.cancel()
        await dictating.cancel()

        #expect(transcribing.module is SpeechTranscriber)
        #expect(dictating.module is DictationTranscriber)
    }
#endif

@available(iOS 26, macOS 26, *)
@MainActor
@Test func theModelsResultsBecomeTheCandidatesTheSpokenSetReads() async throws {
    let results = [
        Phrase("135 four", from: 0, to: 1, isFinal: false),
        Phrase("135 for", "135 four", from: 0, to: 1.2, isFinal: true),
        Phrase(" 4,", " four,", from: 1.2, to: 1.8, isFinal: true),
        Phrase(" 8 reps", from: 1.8, to: 2.4, isFinal: false)
    ]
    var captions: [String] = []

    let segments = try await OnDeviceSpeech.segments(of: results.async) { captions.append($0) }

    #expect(captions == ["135 four", "135 for", "135 for 4,", "135 for 4, 8 reps"])
    #expect(segments.candidates == ["135 for 4, 8 reps", "135 four 4, 8 reps", "135 for four, 8 reps"])
}

@available(iOS 26, macOS 26, *)
extension Array where Element: Sendable {
    fileprivate var async: AsyncStream<Element> {
        AsyncStream { continuation in
            forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

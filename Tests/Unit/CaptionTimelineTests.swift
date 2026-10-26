import AVFoundation
import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aPacedHearTimesEachNewCaptionFromWhenPlaybackBegan() {
    let clock = ManualListeningClock()
    let timeline = CaptionTimeline(clock: clock)
    timeline.hear("warming up")
    clock.advance(by: .milliseconds(250))
    timeline.start()
    clock.advance(by: .milliseconds(900))
    timeline.hear("135")
    clock.advance(by: .milliseconds(100))
    timeline.hear("135")
    clock.advance(by: .milliseconds(200))
    timeline.hear("135 for 5 at 8.")

    #expect(
        timeline.captions == [HearReport.Caption(atMs: 900, heard: "135"), HearReport.Caption(atMs: 1200, heard: "135 for 5 at 8.")],
        "a caption before playback and a repeat of the last are not new captions"
    )
}

@available(macOS 26, *)
@MainActor
@Test func aRecordingPlaysInTheMicTapsBuffersWithTheLastOneShort() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let tap = 1365
    let written = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(tap * 2 + 100)))
    written.frameLength = written.frameCapacity
    try AVAudioFile(forWriting: url, settings: format.settings).write(from: written)

    let buffers = try SpeechListening.tapBuffers(of: AVAudioFile(forReading: url))

    #expect(buffers.map(\.frameLength) == [AVAudioFrameCount(tap), AVAudioFrameCount(tap), 100])
}

import Testing

@testable import WorkoutTracker

private let quiet: Float = -60
private let loud: Float = -20

private func frames(_ count: Int, at level: Float) -> [Float] {
    Array(repeating: level, count: count)
}

@Test func aRoomThatStaysQuietNeverSpeaks() {
    let voice = VoiceActivity(levels: frames(40, at: quiet))

    #expect(!voice.hasSpoken)
    #expect(voice.pause == nil)
}

@Test func oneLoudFrameIsNotSpeechAndTwoInARowAre() {
    let clank = VoiceActivity(levels: frames(3, at: quiet) + [loud] + frames(5, at: quiet))
    let speech = VoiceActivity(levels: frames(3, at: quiet) + frames(2, at: loud))

    #expect(!clank.hasSpoken)
    #expect(clank.pause == nil)
    #expect(speech.hasSpoken)
    #expect(speech.pause == nil, "no pause while the athlete speaks")
}

@Test func theFirstFramesAreNeverLoudBecauseTheFloorHasNothingToReadYet() {
    let voice = VoiceActivity(levels: frames(2, at: loud) + frames(10, at: quiet))

    #expect(!voice.hasSpoken)
}

@Test func aPauseCountsTheQuietFramesSinceTheLastLoudOne() {
    let voice = VoiceActivity(levels: frames(3, at: quiet) + frames(5, at: loud) + frames(4, at: quiet))

    #expect(voice.pause == VoiceActivity.Pause(frames: 4, began: 8 * VoiceActivity.frameSamples))
    #expect(voice.isPaused(since: 8 * VoiceActivity.frameSamples))
    #expect(!voice.isPaused(since: 8 * VoiceActivity.frameSamples - 1), "a read of less audio missed the last word")
}

@Test func speechResumingEndsThePauseAndTheNextPauseBeginsAfterIt() {
    let said = frames(3, at: quiet) + frames(5, at: loud) + frames(4, at: quiet)
    let resumed = VoiceActivity(levels: said + frames(2, at: loud))
    let pausedAgain = VoiceActivity(levels: said + frames(2, at: loud) + frames(1, at: quiet))

    #expect(resumed.pause == nil)
    #expect(!resumed.isPaused(since: 12 * VoiceActivity.frameSamples))
    #expect(pausedAgain.pause == VoiceActivity.Pause(frames: 1, began: 14 * VoiceActivity.frameSamples))
}

@Test func aLoudFrameInAPauseStartsItOver() {
    let voice = VoiceActivity(levels: frames(3, at: quiet) + frames(5, at: loud) + frames(4, at: quiet) + [loud] + frames(2, at: quiet))

    #expect(voice.pause == VoiceActivity.Pause(frames: 2, began: 13 * VoiceActivity.frameSamples))
}

@Test func levelsHeardInPiecesReadAsLevelsHeardAtOnce() {
    let levels = frames(3, at: quiet) + frames(5, at: loud) + frames(4, at: quiet)
    var pieces = VoiceActivity()
    pieces.hear(levels[..<4])
    pieces.hear(levels[4...])

    #expect(pieces == VoiceActivity(levels: levels))
    #expect(pieces.frames == 12)
}

/// Noise 30 dB over the room reads as speech until it has lasted long enough to be the floor: 18
/// frames on, the 15th percentile is within 9 dB of it. Speech over it is still heard.
@Test func noiseThatRisesAndStaysBecomesTheFloor() {
    let risen = frames(3, at: quiet) + frames(40, at: -30)
    let noisy = VoiceActivity(levels: risen)
    let spokenOver = VoiceActivity(levels: risen + frames(2, at: -15))

    #expect(noisy.pause == VoiceActivity.Pause(frames: 25, began: 18 * VoiceActivity.frameSamples))
    #expect(spokenOver.pause == nil)
}

import Testing

@testable import WorkoutTracker

@Test func restPillUrgencyCueIntensifiesAcrossFinalFiveSeconds() {
    let firstBeat = RestPillUrgencyCue(remaining: 5, reduceMotion: false)
    let finalBeat = RestPillUrgencyCue(remaining: 1, reduceMotion: false)

    #expect(firstBeat.isActive)
    #expect(firstBeat.shouldBreathe)
    #expect(finalBeat.accentIntensity > firstBeat.accentIntensity)
    #expect(finalBeat.accentIntensity == 1)
}

@Test func restPillUrgencyCueReducedMotionUsesSingleTintShift() {
    let cue = RestPillUrgencyCue(remaining: 5, reduceMotion: true)

    #expect(cue.isActive)
    #expect(!cue.shouldBreathe)
    #expect(cue.breathScale == 1)
    #expect(cue.accentIntensity == 1)
}

@Test func restPillUrgencyCueStaysQuietBeforeFinalFiveSeconds() {
    let cue = RestPillUrgencyCue(remaining: 6, reduceMotion: false)

    #expect(!cue.isActive)
    #expect(!cue.shouldBreathe)
    #expect(cue.breathScale == 1)
    #expect(cue.accentIntensity == 0)
}

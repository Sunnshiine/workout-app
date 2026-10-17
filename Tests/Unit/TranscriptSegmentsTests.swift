import Testing

@testable import WorkoutTracker

private func segment(_ top: String, _ alternatives: String...) -> TranscriptSegments.Segment {
    TranscriptSegments.Segment(top: top, alternatives: alternatives)
}

@Test func whatIsHeardIsTheFinishedPhrasesThenTheLatestTentativeOne() {
    var segments = TranscriptSegments()

    segments.receive(segment("135"), from: 0, to: 0.5, isFinal: false)
    segments.receive(segment("135 for"), from: 0, to: 1, isFinal: false)
    #expect(segments.heard == "135 for")

    segments.receive(segment("135 for 4"), from: 0, to: 1.5, isFinal: true)
    segments.receive(segment(" at"), from: 1.5, to: 2, isFinal: false)
    segments.receive(segment(" at RPE 9."), from: 1.5, to: 2.5, isFinal: false)
    #expect(segments.heard == "135 for 4 at RPE 9.")
}

@Test func aFinishedPhraseReplacesTheTentativeOneItCovers() {
    var segments = TranscriptSegments()

    segments.receive(segment("85 for 5 and"), from: 0.4, to: 2, isFinal: false)
    segments.receive(segment("185 for 5 at 8."), from: 0, to: 2.5, isFinal: true)

    #expect(segments.heard == "185 for 5 at 8.")
    #expect(segments.candidates == ["185 for 5 at 8."])
}

@Test func aTentativePhraseNeverTakesBackAFinishedOne() {
    var segments = TranscriptSegments()

    segments.receive(segment("185 for 5"), from: 0, to: 2, isFinal: true)
    segments.receive(segment(" at 8."), from: 1.8, to: 3, isFinal: false)

    #expect(segments.heard == "185 for 5 at 8.")
}

@Test func aPhraseFinishedAfterTheNextOneBeganStillReadsFirst() {
    var segments = TranscriptSegments()

    segments.receive(segment("185 for 5"), from: 0, to: 1.5, isFinal: false)
    segments.receive(segment(" at 8."), from: 1.5, to: 2.5, isFinal: false)
    segments.receive(segment("185 for 5"), from: 0, to: 1.5, isFinal: true)

    #expect(segments.heard == "185 for 5 at 8.")
}

@Test func aTranscriberThatNeverFinishesAPhraseIsHeardByItsLastResult() {
    var segments = TranscriptSegments()

    segments.receive(segment("135 for four", "135 for four"), from: 0, to: 1, isFinal: false)
    segments.receive(
        segment("135 for four at RPE nine", "135 for four at RPE nine", "135 for four RTE nine"),
        from: 0,
        to: 2,
        isFinal: false
    )

    #expect(segments.candidates == ["135 for four at RPE nine", "135 for four RTE nine"])
}

@Test func aPhraseRevisedOverNoLengthOfAudioStillReplacesItself() {
    var segments = TranscriptSegments()

    segments.receive(segment("135"), from: 0, to: 0, isFinal: false)
    segments.receive(segment("135 for 4"), from: 0, to: 0, isFinal: false)

    #expect(segments.heard == "135 for 4")
}

@Test func aTranscriberThatNeverFinishesKeepsEachPhraseItHeardWithASpaceBetween() {
    var segments = TranscriptSegments()

    segments.receive(segment("185 for 5"), from: 0, to: 1.5, isFinal: false)
    segments.receive(segment("at 8"), from: 1.5, to: 2.5, isFinal: false)

    #expect(segments.heard == "185 for 5 at 8")
}

@Test func candidatesAreTheTopTranscriptThenEachPhraseSwappedForOneOfItsAlternatives() {
    var segments = TranscriptSegments()

    segments.receive(segment("18545 at", "18545 at", "185 or 5 at", "18545, at"), from: 0, to: 1.5, isFinal: true)
    segments.receive(segment(" nine.", " nine.", " 9."), from: 1.5, to: 2, isFinal: true)

    #expect(segments.candidates == ["18545 at nine.", "185 or 5 at nine.", "18545, at nine.", "18545 at 9."])
}

@Test func swapsThatSpellTheSameTranscriptAreOneCandidate() {
    var segments = TranscriptSegments()

    segments.receive(segment("Skip.", "Skip.", " Skip. "), from: 0, to: 1, isFinal: true)

    #expect(segments.candidates == ["Skip."])
}

@Test func silenceIsNothingHeard() {
    var segments = TranscriptSegments()
    #expect(segments.candidates.isEmpty)

    segments.receive(segment(" ", " "), from: 0, to: 1, isFinal: false)

    #expect(segments.heard.isEmpty)
    #expect(segments.candidates.isEmpty)
}

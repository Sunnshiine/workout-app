import Testing

@testable import WorkoutTracker

private func segment(_ top: String, _ alternatives: String...) -> TranscriptSegments.Segment {
    TranscriptSegments.Segment(top: top, alternatives: alternatives)
}

@Test func whatIsHeardIsTheFinishedPhrasesThenTheLatestTentativeOne() {
    var segments = TranscriptSegments()

    segments.receive(segment("135"), isFinal: false)
    segments.receive(segment("135 for"), isFinal: false)
    #expect(segments.heard == "135 for")

    segments.receive(segment("135 for 4"), isFinal: true)
    segments.receive(segment(" at"), isFinal: false)
    segments.receive(segment(" at RPE 9."), isFinal: false)
    #expect(segments.heard == "135 for 4 at RPE 9.")
}

@Test func aFinishedPhraseReplacesTheTentativeOneItCovers() {
    var segments = TranscriptSegments()

    segments.receive(segment("185 for 5 and"), isFinal: false)
    segments.receive(segment("185 for 5 at 8."), isFinal: true)

    #expect(segments.heard == "185 for 5 at 8.")
    #expect(segments.candidates == ["185 for 5 at 8."])
}

@Test func aTranscriberThatNeverFinishesAPhraseIsHeardByItsLastResult() {
    var segments = TranscriptSegments()

    segments.receive(segment("135 for four", "135 for four"), isFinal: false)
    segments.receive(segment("135 for four at RPE nine", "135 for four at RPE nine", "135 for four RTE nine"), isFinal: false)

    #expect(segments.candidates == ["135 for four at RPE nine", "135 for four RTE nine"])
}

@Test func candidatesAreTheTopTranscriptThenEachPhraseSwappedForOneOfItsAlternatives() {
    var segments = TranscriptSegments()

    segments.receive(segment("18545 at", "18545 at", "185 or 5 at", "18545, at"), isFinal: true)
    segments.receive(segment(" nine.", " nine.", " 9."), isFinal: true)

    #expect(segments.candidates == ["18545 at nine.", "185 or 5 at nine.", "18545, at nine.", "18545 at 9."])
}

@Test func swapsThatSpellTheSameTranscriptAreOneCandidate() {
    var segments = TranscriptSegments()

    segments.receive(segment("Skip.", "Skip.", " Skip. "), isFinal: true)

    #expect(segments.candidates == ["Skip."])
}

@Test func silenceIsNothingHeard() {
    var segments = TranscriptSegments()
    #expect(segments.candidates.isEmpty)

    segments.receive(segment(" ", " "), isFinal: false)

    #expect(segments.heard.isEmpty)
    #expect(segments.candidates.isEmpty)
}

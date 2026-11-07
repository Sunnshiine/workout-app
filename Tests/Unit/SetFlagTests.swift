import Testing

@testable import WorkoutTracker

private func flag(_ kind: SetFlagKind, _ text: String? = nil) throws -> SetFlag {
    try #require(SetFlag(kind: kind, text: text))
}

@Test func aSetFlagReadsAsThePlainSentenceTheCoachReads() throws {
    let line = try SetFlagLine(setIndex: 1, flag: flag(.pain, "left hip pinch on the way up"))
    #expect(line.text == "Set 2 · Pain: left hip pinch on the way up")
    #expect(try SetFlagLine(setIndex: 0, flag: flag(.technique)).text == "Set 1 · Technique")
}

@Test(arguments: SetFlagKind.allCases)
func aSetFlagLineReadsBackAsTheFlagItWasWrittenFrom(kind: SetFlagKind) throws {
    let line = try SetFlagLine(setIndex: 4, flag: flag(kind, "front squat: belt broke"))
    #expect(SetFlagLine(parsing: line.text) == line)
}

@Test(arguments: [
    "keep the hips down",
    "Set 2",
    "Set 2 - Pain",
    "Set 2 · Ache: left hip",
    "set 2 · Pain",
    "Set 0 · Pain",
    "Set 2 · Other",
    ""
])
func aCoachsOwnWordsAreNotASetFlag(line: String) {
    #expect(SetFlagLine(parsing: line) == nil)
}

@Test func otherNeedsWordsBecauseAloneItTellsTheCoachNothing() {
    #expect(SetFlag(kind: .other, text: nil) == nil)
    #expect(SetFlag(kind: .other, text: "  \n ") == nil)
    #expect(SetFlag(kind: .other, text: "gym closes early")?.text == "gym closes early")
}

@Test func blankWordsAreNoWordsOnTheOtherKinds() throws {
    #expect(try flag(.pain, "   ").text == nil)
}

@Test func wordsFitOneLineSoALaterSyncReadsTheLineBack() throws {
    let spread = try flag(.pain, "  left hip\nthen\r\nright knee \n")
    #expect(spread.text == "left hip then right knee")
    let line = SetFlagLine(setIndex: 0, flag: spread)
    #expect(SetFlagLine.all(in: line.text) == [line])
}

@Test func wordsStopAtTheLengthALineCanCarry() {
    #expect(SetFlag(kind: .pain, text: String(repeating: "a", count: SetFlag.maximumTextLength)) != nil)
    #expect(SetFlag(kind: .pain, text: String(repeating: "a", count: SetFlag.maximumTextLength + 1)) == nil)
}

@Test func aSetFlagLineStartsAnEmptyCellNote() {
    #expect(SetFlagLine.cellNote("", adding: "Set 1 · Pain") == "Set 1 · Pain")
}

@Test func aSetFlagLineLeavesTheCoachsWordsVerbatimAndGoesOnANewLine() {
    let coach = "  Watch   the hips\n\nthen brace "
    #expect(SetFlagLine.cellNote(coach, adding: "Set 1 · Pain") == "\(coach)\nSet 1 · Pain")
}

@Test func aNoteEndingInANewLineTakesTheLineWithNoBlankLine() {
    #expect(SetFlagLine.cellNote("Brace\n", adding: "Set 1 · Pain") == "Brace\nSet 1 · Pain")
}

@Test func aLineTheNoteAlreadyHoldsIsNotAddedAgainSoAReplayConverges() {
    let note = "Brace\nSet 1 · Pain\nSet 2 · Technique"
    #expect(SetFlagLine.cellNote(note, adding: "Set 1 · Pain") == note)
}

@Test func theLinesOfANoteSkipTheCoachsWordsAroundThem() throws {
    let lines = SetFlagLine.all(in: "Brace\nSet 1 · Pain: left hip\nGood work\nSet 3 · Swapped")
    #expect(try lines == [SetFlagLine(setIndex: 0, flag: flag(.pain, "left hip")), SetFlagLine(setIndex: 2, flag: flag(.swapped))])
}

@MainActor
@Test func theSetsOneMarkSpeaksForTheFlagThatMostNeedsTheAthlete() throws {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE7", percentOneRM: nil, state: .logged)
    #expect(set.setFlagStanding == nil)

    set.record(try flag(.pain), standing: .landed)
    #expect(set.setFlagStanding == .landed)

    set.record(try flag(.technique), standing: .unsynced)
    #expect(set.setFlagStanding == .unsynced)

    set.record(try flag(.swapped), standing: .refused)
    #expect(set.setFlagStanding == .refused)
}

@MainActor
@Test func theSameFlagRaisedTwiceIsOneEntryLikeItsOneLineInTheSheet() throws {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE7", percentOneRM: nil, state: .logged)
    set.record(try flag(.pain, "left hip"), standing: .landed)
    set.record(try flag(.pain, "left hip"), standing: .unsynced)
    #expect(set.setFlags == [SetFlagEntry(flag: try flag(.pain, "left hip"), standing: .unsynced)])
}

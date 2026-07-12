import Testing

@testable import WorkoutTracker

@Test func classifiesEmptyTokenAsPending() {
    let classification = SetLogToken.classify("")

    #expect(classification.state == .pending)
    #expect(classification.setLog == nil)
    #expect(classification.unstructuredSetLog == nil)
}

@Test func classifiesWhitespaceOnlyTokenAsPending() {
    let classification = SetLogToken.classify("   ")

    #expect(classification.state == .pending)
    #expect(classification.setLog == nil)
    #expect(classification.unstructuredSetLog == nil)
}

@Test func classifiesSkipSentinelAsSkippedFoldingCase() {
    for token in ["skip", "SKIP", "Skip", "  skip  "] {
        let classification = SetLogToken.classify(token)

        #expect(classification.state == .skipped)
        #expect(classification.setLog == nil)
        #expect(classification.unstructuredSetLog == nil)
    }
}

@Test func classifiesStructuredSetLogAsLogged() {
    let classification = SetLogToken.classify("185x5@8")

    #expect(classification.state == .logged)
    #expect(classification.setLog?.formatted == "185x5@8")
    #expect(classification.unstructuredSetLog == nil)
}

@Test func classifiesFreeTextAsUnstructuredLogged() {
    let classification = SetLogToken.classify("felt heavy")

    #expect(classification.state == .logged)
    #expect(classification.setLog == nil)
    #expect(classification.unstructuredSetLog == "felt heavy")
}

@Test func isSetLogListValueAcceptsEmptySkipAndStructuredLog() {
    #expect(SetLogToken.isSetLogListValue(""))
    #expect(SetLogToken.isSetLogListValue("skip"))
    #expect(SetLogToken.isSetLogListValue("SKIP"))
    #expect(SetLogToken.isSetLogListValue("185x5@8"))
}

@Test func isSetLogListValueRejectsFreeText() {
    #expect(!SetLogToken.isSetLogListValue("Coach note"))
    #expect(!SetLogToken.isSetLogListValue("225"))
}

@Test func compactAggregateHeaderRequiresMoreThanOneEntry() {
    // A single Set-Log-list token is not a compact aggregate header.
    #expect(!SetLogToken.isCompactAggregateHeader("185x5@8", setCount: 3))
}

@Test func compactAggregateHeaderAcceptsCountWithinSetCount() {
    #expect(SetLogToken.isCompactAggregateHeader("185x5@8, 195x5@9", setCount: 3))
    #expect(SetLogToken.isCompactAggregateHeader("185x5@8, skip, ", setCount: 3))
}

@Test func compactAggregateHeaderRejectsCountAboveSetCount() {
    // Three entries against a two-Set prescription exceeds the count <= setCount bound.
    #expect(!SetLogToken.isCompactAggregateHeader("185x5@8, 195x5@9, skip", setCount: 2))
}

@Test func compactAggregateHeaderAcceptsCountEqualToSetCount() {
    #expect(SetLogToken.isCompactAggregateHeader("185x5@8, 195x5@9, skip", setCount: 3))
}

@Test func compactAggregateHeaderRejectsWhenAnyEntryIsFreeText() {
    #expect(!SetLogToken.isCompactAggregateHeader("185x5@8, Coach note", setCount: 3))
}

@Test func serializesStructuredSetLogAsFormattedToken() {
    let classification = SetLogToken.Classification(
        state: .logged, setLog: SetLog(formatted: "185x5@8"), unstructuredSetLog: nil)

    #expect(SetLogToken.serialize(classification) == "185x5@8")
}

@Test func serializesUnstructuredSetLogAsFreeText() {
    let classification = SetLogToken.Classification(
        state: .logged, setLog: nil, unstructuredSetLog: "felt heavy")

    #expect(SetLogToken.serialize(classification) == "felt heavy")
}

@Test func serializesSkippedStateAsSkipSentinel() {
    let classification = SetLogToken.Classification(state: .skipped, setLog: nil, unstructuredSetLog: nil)

    #expect(SetLogToken.serialize(classification) == SetLogToken.skipSentinel)
}

@Test func serializesPendingStateAsEmptyToken() {
    let classification = SetLogToken.Classification(state: .pending, setLog: nil, unstructuredSetLog: nil)

    #expect(SetLogToken.serialize(classification) == "")
}

@Test func serializePrefersStructuredSetLogOverUnstructuredText() {
    // A Set can carry both a structured and an unstructured Set Log (ExerciseSet stores them
    // independently, and displayReps gives the structured one precedence). `classify` never
    // yields both, so the round-trip below can't reach this case — pin it directly: the
    // structured token wins, never the free text.
    let classification = SetLogToken.Classification(
        state: .logged, setLog: SetLog(formatted: "185x5@8"), unstructuredSetLog: "felt heavy")

    #expect(SetLogToken.serialize(classification) == "185x5@8")
}

@Test func roundTripsEmptySkipStructuredAndUnstructuredTokens() {
    for token in ["", "skip", "185x5@8", "felt heavy"] {
        let first = SetLogToken.classify(token)
        let second = SetLogToken.classify(SetLogToken.serialize(first))

        #expect(second == first)
    }
}

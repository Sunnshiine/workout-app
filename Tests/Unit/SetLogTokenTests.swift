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

@Test func skipSentinelConstantIsSkip() {
    #expect(SetLogToken.skipSentinel == "skip")
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
    let log = SetLog(formatted: "185x5@8")

    #expect(SetLogToken.serialize(state: .logged, setLog: log, unstructuredSetLog: nil) == "185x5@8")
}

@Test func serializesUnstructuredSetLogAsFreeText() {
    #expect(SetLogToken.serialize(state: .logged, setLog: nil, unstructuredSetLog: "felt heavy") == "felt heavy")
}

@Test func serializesSkippedStateAsSkipSentinel() {
    #expect(SetLogToken.serialize(state: .skipped, setLog: nil, unstructuredSetLog: nil) == SetLogToken.skipSentinel)
}

@Test func serializesPendingStateAsEmptyToken() {
    #expect(SetLogToken.serialize(state: .pending, setLog: nil, unstructuredSetLog: nil) == "")
}

@Test func roundTripsEmptySkipStructuredAndUnstructuredTokens() {
    for token in ["", "skip", "185x5@8", "felt heavy"] {
        let first = SetLogToken.classify(token)
        let serialized = SetLogToken.serialize(
            state: first.state,
            setLog: first.setLog,
            unstructuredSetLog: first.unstructuredSetLog
        )
        let second = SetLogToken.classify(serialized)

        #expect(second == first)
    }
}

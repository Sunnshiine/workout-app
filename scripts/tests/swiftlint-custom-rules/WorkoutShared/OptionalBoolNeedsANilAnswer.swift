enum OptionalBoolNeedsANilAnswer {
    static func optionalChainComparedToFalseIsFlagged(state: ContentState?) -> Bool {
        state?.isResting == false
    }
}

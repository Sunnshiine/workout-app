enum OptionalBoolNeedsANilAnswer {
    static func optionalChainComparedToFalseIsFlagged(session: Session?) -> Bool {
        session?.isComplete == false
    }
}

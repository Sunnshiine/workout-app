struct OptionalBoolNeedsANilAnswer {
    func optionalChainComparedToFalseIsFlagged(session: Session?) -> Bool {
        session?.isComplete == false
    }

    func optionalChainNotEqualToTrueIsFlagged(session: Session?) -> Bool {
        session?.isComplete != true
    }

    func tryOptionalComparedToTrueIsFlagged(store: SessionStore) -> Bool {
        (try? store.isPending()) == true
    }

    func mapComparedToTrueIsFlagged(session: Session?) -> Bool {
        session.map(\.isComplete) == true
    }

    func flatMapNotEqualToFalseIsFlagged(session: Session?) -> Bool {
        session.flatMap(\.isPending) != false
    }

    func optionalChainedCallComparedToTrueIsFlagged(store: SessionStore?) -> Bool {
        store?.isPending() == true
    }

    func comparisonInAStringIsFalselyFlagged() -> String {
        "session?.isComplete == true"
    }

    func reversedComparisonIsMissed(session: Session?) -> Bool {
        true == session?.isComplete
    }

    func chainPastACallIsMissed(store: SessionStore?) -> Bool {
        store?.current().isComplete == true
    }

    func plainOptionalBoolIsMissed(isComplete: Bool?) -> Bool {
        isComplete == true
    }

    func mapWithATrailingClosureComparedToTrueIsFlagged(session: Session?) -> Bool {
        session.map { $0.isComplete } == true
    }

    func flatMapWithATrailingClosureNotEqualToFalseIsFlagged(session: Session?) -> Bool {
        session.flatMap { $0.isPending } != false
    }

    func comparisonInACommentPasses(session: Session?) -> Bool {
        // session?.isComplete == true
        session?.isComplete ?? false
    }

    func comparisonInADocCommentPasses(session: Session?) -> Bool {
        /// session?.isComplete == true
        session?.isComplete ?? false
    }
}

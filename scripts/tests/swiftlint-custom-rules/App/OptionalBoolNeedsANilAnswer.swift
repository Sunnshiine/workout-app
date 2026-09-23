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

    func reversedComparisonPasses(session: Session?) -> Bool {
        true == session?.isComplete
    }

    func chainPastACallPasses(store: SessionStore?) -> Bool {
        store?.current().isComplete == true
    }

    func plainOptionalBoolPasses(isComplete: Bool?) -> Bool {
        isComplete == true
    }

    func mapWithATrailingClosurePasses(session: Session?) -> Bool {
        session.map { $0.isComplete } == true
    }

    func comparisonInACommentPasses(session: Session?) -> Bool {
        // session?.isComplete == true
        session?.isComplete ?? false
    }
}

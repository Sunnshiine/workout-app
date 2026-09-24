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

    func optionalChainedCallWithANestedCallIsMissed(store: SessionStore?) -> Bool {
        store?.isPending(for: current()) == true
    }

    func optionalSubscriptIsMissed(sessions: [Session]?) -> Bool {
        sessions?[0].isComplete == true
    }

    func mapThenANonOptionalCallIsFalselyFlagged(reps: [Int]) -> Bool {
        reps.map(abs).contains(1) == true
    }

    func mapThenATrailingClosureCallIsFalselyFlagged(sessions: [Session]) -> Bool {
        sessions.map { $0.isComplete }.allSatisfy { $0 } == true
    }

    func mapWithAClosureThatSpansLinesIsMissed(session: Session?) -> Bool {
        session.map {
            $0.isComplete
        } == true
    }

    func flatMapWithAnArgumentThatSpansLinesIsMissed(session: Session?) -> Bool {
        session.flatMap(
            \.isPending
        ) != false
    }

    func tryOptionalThatSpansLinesIsMissed(store: SessionStore) -> Bool {
        (try?
            store.isPending()) == true
    }
}

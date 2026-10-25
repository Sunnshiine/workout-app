enum ExerciseReferencesAreParsed {
    static func implicitMemberMintIsFlagged() -> ExerciseReference {
        .unchecked(name: "Back Squat", ordinal: 1)
    }

    static func qualifiedMintIsFlagged() -> ExerciseReference {
        ExerciseReference.unchecked(name: "Back Squat", ordinal: 1)
    }

    static func mintBrokenAfterTheParenIsFlagged() -> ExerciseReference {
        .unchecked(
            name: "Back Squat",
            ordinal: 1
        )
    }

    static func memberOnTheNextLineIsFlagged() -> ExerciseReference {
        ExerciseReference
            .unchecked(name: "Back Squat", ordinal: 1)
    }

    static func unappliedMintIsFlagged() -> ExerciseReference {
        let mint = ExerciseReference.unchecked
        return mint("Back Squat", 1)
    }

    static func mintNamedAsAFunctionIsFlagged() -> (ExerciseName, Int) -> ExerciseReference {
        ExerciseReference.unchecked(name:ordinal:)
    }

    static func anotherTypesUncheckedFactoryIsFalselyFlagged() -> Checkbox {
        .unchecked(name: "Warm-up done")
    }

    static func aliasedUnappliedMintIsMissed() -> ExerciseReference {
        typealias Reference = ExerciseReference
        let mint = Reference.unchecked
        return mint("Back Squat", 1)
    }

    static func parsedReferencePasses(_ exercise: Exercise, in session: Session) -> ExerciseReference {
        exercise.reference(in: session)
    }

    static func uncheckedSendablePasses() {
        final class Box: @unchecked Sendable {}
    }

    static func enumCaseNamedUncheckedPasses(_ box: Checkbox) -> Bool {
        box == .unchecked
    }

    static func mintInACommentPasses() {
        // .unchecked(name: "Back Squat", ordinal: 1)
    }

    static func mintInADocCommentPasses() {
        /// `.unchecked(name: "Back Squat", ordinal: 1)` names the second Back Squat.
    }

    static func mintInAStringPasses() -> String {
        ".unchecked(name: \"Back Squat\", ordinal: 1)"
    }
}

extension ExerciseReference {
    static func bareMintInAnExtensionIsFlagged() -> ExerciseReference {
        unchecked(name: "Back Squat", ordinal: 1)
    }

    static func mintThroughSelfIsFlagged() -> ExerciseReference {
        Self.unchecked(name: "Back Squat", ordinal: 1)
    }
}

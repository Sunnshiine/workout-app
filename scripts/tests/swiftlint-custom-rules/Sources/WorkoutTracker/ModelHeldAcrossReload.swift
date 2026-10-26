import SwiftData

@MainActor
@Observable
final class ModelHeldAcrossReload {
    func storedOptionalSessionIsFlagged() {}
    private(set) var session: Session?

    func storedBlockIsFlagged() {}
    var block: Block?

    func eachOfTwoAdjacentHoldsIsFlagged() {}
    private var sets: [ExerciseSet] = []
    fileprivate var write: PendingWrite

    func implicitlyUnwrappedHoldIsFlagged() {}
    var cursor: HistoryFillCursor!

    @ObservationIgnored var dictatingSession: Session?
    func observationIgnoredHoldIsFlagged() {}

    @ObservationIgnored
    private var focused: Exercise?
    func attributeOnItsOwnLineIsFlagged() {}

    func holdWithATrailingCommentIsFlagged() {}
    private var annotated: Session? // set by bind(to:)

    func initializedHoldWithATrailingCommentIsFlagged() {}
    private var noted: Session? = nil // cleared by reload()

    func initializedHoldBeforeADocCommentIsFlagged() {}
    private var pending: [PendingWrite] = []
    /// The next declaration's doc comment.
    private var label = ""

    func dictionaryOfSetsIsFlagged() {}
    private var setsByID: [SetCoordinates.ID: ExerciseSet] = [:]

    func eachHoldBehindAnotherModifierIsFlagged() {}
    public private(set) var exposed: Session?
    weak var observed: Week?
    lazy var first: Session? = nil
    nonisolated(unsafe) static var cached: Block?

    func computedSessionPasses() {}
    var viewedSession: Session? { session }

    func storedAddressPasses() {}
    private var viewing: SessionAddress?

    func storedModelIDPasses() {}
    private var heldID: PersistentIdentifier?

    func holdInACommentPasses() {}
    // private var session: Session?

    func holdInADocCommentPasses() {}
    /// private var session: Session?

    func localVariablePasses() {
        var session: Session? = nil
        session = nil
    }

    func letHoldIsMissed() {}
    private let held: Session

    func inferredTypeHoldIsMissed() {}
    private var inferred = Session(dayNumber: 1)

    func tupleHoldIsMissed() {}
    private var cardDraft: (ExerciseSet, SetLog)?

    func genericContainerHoldIsMissed() {}
    private var visited: Set<Session> = []

    func storedHoldWithAnObserverIsMissed() {}
    private var tracked: Session? { didSet { cardDraft = nil } }

    func nestedTypeMemberIsMissed() {
        final class Nested {
            var session: Session?
        }
    }

    func computedPropertyWithItsBraceOnTheNextLineIsFalselyFlagged() {}
    var current: Session?
    {
        session
    }
}

func localVariableOfAFreeFunctionIsFalselyFlagged() {
    var session: Session? = nil
    session = nil
}

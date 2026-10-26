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

final class ModelHeldAcrossReloadSpelledOtherwise {
    func optionalSpelledOutIsFlagged() {}
    private var wrapped: Optional<Session>

    func moduleQualifiedHoldIsFlagged() {}
    private var qualified: WorkoutTracker.Session?

    func moduleQualifiedArrayIsFlagged() {}
    private var qualifiedSets: [WorkoutTracker.ExerciseSet] = []

    func holdBeforeABlockCommentIsFlagged() {}
    private var blockCommented: Session? /* set by bind(to:) */

    func optionalSpelledOutAddressPasses() {}
    private var address: Optional<SessionAddress>

    func resultHoldIsMissed() {}
    private var outcome: Result<Session, Error>?

    func taskHoldIsMissed() {}
    private var loading: Task<Session?, Never>?

    func closureHoldIsMissed() {}
    private var resolve: (() -> Session?)?

    func collectionInsideACollectionIsMissed() {}
    private var sessionsByTab: [String: [Session]] = [:]

    func memberOfATypeNestedInATypeIsMissed() {}
    struct Snapshot {
        var session: Session?
    }
}

import Foundation

/// What the last finished sync step concluded, as the `workout` CLI prints it:
/// `{"count":1,"messages":[],"status":"writesQueued"}`.
///
/// One status per `SyncOutcome` case, so an agent tells a failed local write from a parser
/// footnote by reading `status` rather than by matching a sentence. `messages` carries the
/// strings the step produced, verbatim; the sentence the athlete reads is
/// `SyncStatusBannerPresentation`'s and never reaches the wire.
///
/// There is no in-flight status. Being in flight is not an outcome (`SyncCoordinator.isSyncing`
/// answers that, #595), and every CLI command awaits its sync before it builds a report.
public struct SyncOutcomeSnapshot: Encodable, Equatable, Sendable {
    /// One name per `SyncOutcome` case. These names are the wire contract, so renaming one is a
    /// JSON change.
    public enum Status: String, Encodable, Sendable {
        case clear
        case localWriteFailed
        case sheetUnreachable
        case writesQueued
        case writesRefused
        case noBlockTab
        case parseWarnings
        case historyFillFailed
    }

    public let status: Status
    /// Verbatim from the step that produced them; empty for an outcome that carries none.
    public let messages: [String]
    /// Queued writes still waiting for a flush. Only `writesQueued` sets it.
    public let count: Int?

    private init(status: Status, messages: [String] = [], count: Int? = nil) {
        self.status = status
        self.messages = messages
        self.count = count
    }

    init(_ outcome: SyncOutcome) {
        switch outcome {
        case .clear:
            self.init(status: .clear)
        case .localWriteFailed(let message):
            self.init(status: .localWriteFailed, messages: [message])
        case .sheetUnreachable:
            self.init(status: .sheetUnreachable)
        case .writesQueued(let queued):
            self.init(status: .writesQueued, count: queued)
        case .writesRefused(let refusals):
            self.init(status: .writesRefused, messages: refusals)
        case .noBlockTab:
            self.init(status: .noBlockTab)
        case .parseWarnings(let warnings):
            self.init(status: .parseWarnings, messages: warnings)
        case .historyFillFailed(let message):
            self.init(status: .historyFillFailed, messages: [message])
        }
    }
}

public struct BlockSummary: Encodable, Equatable, Sendable {
    public let tabName: String
    public let squatTM: Double?
    public let benchTM: Double?
    public let deadliftTM: Double?
    public let weekCount: Int

    init(_ block: Block) {
        // Flat fields because this is the CLI's wire format, read through the keyed projection so
        // `Block`'s stored columns stay behind one accessor.
        let trainingMaxes = block.trainingMaxes
        tabName = block.tabName
        squatTM = trainingMaxes[.squat]
        benchTM = trainingMaxes[.bench]
        deadliftTM = trainingMaxes[.deadlift]
        weekCount = block.weeks.count
    }
}

public struct SessionSummary: Encodable, Equatable, Sendable {
    public let id: SessionAddress
    public let date: Date?
    public let available: Bool
    public let isComplete: Bool
    public let isCurrent: Bool
    public let completedSetCount: Int
    public let totalSetCount: Int

    init(_ session: Session, id: SessionAddress, isCurrent: Bool) {
        self.id = id
        date = session.date
        available = !session.exercises.isEmpty
        isComplete = session.isComplete
        self.isCurrent = isCurrent
        completedSetCount = session.completedSetCount
        totalSetCount = session.totalSetCount
    }
}

/// A Set's Load Suggestion as the `workout` CLI prints it, one `kind` per case:
/// `{"kind":"estimate","weight":315,"basis":{"origin":"history","setLog":"315x5@7",
/// "session":"Block 27 · W1 D1","text":"from 315x5@7 · W1 D1"}}`. A Set that holds a Set Log
/// reads `{"kind":"none"}`.
public struct LoadSuggestionSnapshot: Encodable, Equatable, Sendable {
    public enum Kind: String, Encodable, Sendable {
        case weight, bodyweight, estimate, none
    }

    public let kind: Kind
    /// `weight` and `estimate` only.
    public let weight: Double?
    /// `estimate` only.
    public let basis: LoadBasisSnapshot?

    @MainActor
    init(for set: ExerciseSet, id: SetAddress, history: LastPerformedLookupSnapshot) {
        switch LoadSuggestionEngine.suggest(for: set, history: history) {
        case .prescribedWeight(let weight):
            (kind, self.weight, basis) = (.weight, weight, nil)
        case .bodyweight:
            (kind, weight, basis) = (.bodyweight, nil, nil)
        case .noSuggestion:
            (kind, weight, basis) = (.none, nil, nil)
        case .estimate(let weight, let loadBasis):
            (kind, self.weight) = (.estimate, weight)
            basis = LoadBasisSnapshot(loadBasis, for: set, id: id)
        }
    }
}

public struct LoadBasisSnapshot: Encodable, Equatable, Sendable {
    public enum Origin: String, Encodable, Sendable {
        case today, history
    }

    public let origin: Origin
    public let setLog: String
    /// `today` only: the Set the basis was logged on.
    public let set: SetAddress?
    /// `history` only: the entry's Session Coordinate.
    public let session: String?
    /// The line the Set card shows under the weight.
    public let text: String
}

extension LoadBasisSnapshot {
    @MainActor
    fileprivate init(_ basis: LoadBasis, for set: ExerciseSet, id: SetAddress) {
        setLog = basis.setLog.formatted
        text = LoadBasisPresentation(basis, for: set).text
        switch basis.origin {
        case .today(let setIndex):
            (origin, self.set, session) = (.today, SetAddress(exercise: id.exercise, index: setIndex), nil)
        case .history(let coordinate):
            (origin, self.set, session) = (.history, nil, coordinate.storageValue)
        }
    }
}

public struct SetSnapshot: Encodable, Equatable, Sendable {
    public let id: SetAddress
    public let index: Int
    /// `pending`, `logged`, or `skipped`.
    public let state: String
    public let prescribedReps: String
    public let prescribedLoad: String
    public let percentOneRM: String?
    public let setLog: String?
    public let unstructuredSetLog: String?
    public let loggedAt: Date?
    public let loadSuggestion: LoadSuggestionSnapshot

    @MainActor
    init(_ set: ExerciseSet, id: SetAddress, history: LastPerformedLookupSnapshot) {
        self.id = id
        index = set.index
        state = set.state.rawValue
        prescribedReps = set.prescribedReps
        prescribedLoad = set.prescribedLoad
        percentOneRM = set.percentOneRM
        setLog = set.setLog?.formatted
        unstructuredSetLog = set.unstructuredSetLog
        loggedAt = set.loggedAt
        loadSuggestion = LoadSuggestionSnapshot(for: set, id: id, history: history)
    }
}

public struct ExerciseSnapshot: Encodable, Equatable, Sendable {
    public let id: ExerciseAddress
    public let order: Int
    public let name: String
    public let baseName: String
    public let cadence: String?
    public let coachNote: String?
    public let legacyLog: String?
    public let isComplete: Bool
    public let sets: [SetSnapshot]

    @MainActor
    init(_ exercise: Exercise, id: ExerciseAddress, history: LastPerformedLookupSnapshot) {
        self.id = id
        order = exercise.order
        name = exercise.name
        baseName = exercise.baseName
        cadence = exercise.cadence
        coachNote = exercise.coachNote
        legacyLog = exercise.legacyLog
        isComplete = exercise.isComplete
        sets = exercise.sets
            .sorted { $0.index < $1.index }
            .map { SetSnapshot($0, id: SetAddress(exercise: id, index: $0.index), history: history) }
    }
}

public struct SessionSnapshot: Encodable, Equatable, Sendable {
    public let id: SessionAddress
    public let date: Date?
    public let available: Bool
    public let isComplete: Bool
    public let isCurrent: Bool
    public let completedSetCount: Int
    public let totalSetCount: Int
    public let exercises: [ExerciseSnapshot]

    @MainActor
    init(_ session: Session, id: SessionAddress, isCurrent: Bool, history: LastPerformedLookupSnapshot) {
        let summary = SessionSummary(session, id: id, isCurrent: isCurrent)
        self.id = id
        date = summary.date
        available = summary.available
        isComplete = summary.isComplete
        self.isCurrent = isCurrent
        completedSetCount = summary.completedSetCount
        totalSetCount = summary.totalSetCount
        exercises = session.exercises
            .sorted { $0.order < $1.order }
            .map { ExerciseSnapshot($0, id: ExerciseAddress(session: id, order: $0.order), history: history) }
    }
}

/// The application at a glance: what is selected, how sync stands, and the Session index.
public struct AppSnapshot: Encodable, Equatable, Sendable {
    public let spreadsheetId: String?
    public let spreadsheetTitle: String?
    public let syncOutcome: SyncOutcomeSnapshot
    public let pendingWriteCount: Int
    public let block: BlockSummary?
    public let currentSession: SessionAddress?
    public let currentSessionReason: String
    public let currentSessionIsOverridden: Bool
    public let viewedSession: SessionAddress?
    public let canMoveOn: Bool
    public let openExercises: [ExerciseAddress]
    public let sessions: [SessionSummary]
}

public struct LogReport: Encodable, Equatable, Sendable {
    public let set: SetSnapshot
    public let pendingWriteCount: Int
    public let exerciseIsComplete: Bool
}

/// `conflictedWrites` lists every queued write whose status is `conflict`, from this flush or an
/// earlier one, because the coordinator never retries those and an agent must see them until
/// they are discarded.
public struct FlushReport: Encodable, Equatable, Sendable {
    public let attempted: Int
    public let written: Int
    public let conflictedWrites: [String]
    public let remainingPendingWrites: Int
    public let syncOutcome: SyncOutcomeSnapshot
}

public struct SyncReport: Encodable, Equatable, Sendable {
    public let syncOutcome: SyncOutcomeSnapshot
    public let block: BlockSummary?
    public let currentSession: SessionAddress?
    /// Equal to `currentSession` unless the athlete had browsed away.
    public let viewedSession: SessionAddress?
    public let pendingWriteCount: Int
    public let conflictedWrites: [String]
}

/// One tab of the Sheet as the client sees it: a sparse A1 map plus hidden rows keyed by their
/// 1-based row number.
public struct SheetTabSnapshot: Equatable, Sendable {
    public let tab: String
    public let cells: [String: String]
    public let hiddenRows: [Int: SheetRowVisibility]

    init(tab: String, snapshot: SheetSnapshot) {
        self.tab = tab
        cells = snapshot.sparseCells
        hiddenRows = snapshot.hiddenRowsByNumber
    }
}

extension SheetTabSnapshot: Encodable {
    private enum CodingKeys: String, CodingKey {
        case tab, cells, hiddenRows
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tab, forKey: .tab)
        try container.encode(cells, forKey: .cells)
        try container.encode(
            Dictionary(uniqueKeysWithValues: hiddenRows.map { (String($0.key), $0.value) }),
            forKey: .hiddenRows
        )
    }
}

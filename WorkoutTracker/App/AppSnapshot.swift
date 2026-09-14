import Foundation

/// The sync coordinator's state as a value: `{"status":"pendingWrites","count":1}`.
public enum SyncStateSnapshot: Equatable, Sendable {
    case idle
    case syncing
    case offline
    case pendingWrites(Int)
    case conflict([String])

    public var status: String {
        switch self {
        case .idle: "idle"
        case .syncing: "syncing"
        case .offline: "offline"
        case .pendingWrites: "pendingWrites"
        case .conflict: "conflict"
        }
    }

    init(_ state: SyncCoordinator.State) {
        switch state {
        case .idle: self = .idle
        case .syncing: self = .syncing
        case .offline: self = .offline
        case .pendingWrites(let count): self = .pendingWrites(count)
        case .conflict(let messages): self = .conflict(messages)
        }
    }
}

extension SyncStateSnapshot: Encodable {
    private enum CodingKeys: String, CodingKey {
        case status, count, messages
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        switch self {
        case .pendingWrites(let count):
            try container.encode(count, forKey: .count)
        case .conflict(let messages):
            try container.encode(messages, forKey: .messages)
        case .idle, .syncing, .offline:
            break
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
        tabName = block.tabName
        squatTM = block.squatTM
        benchTM = block.benchTM
        deadliftTM = block.deadliftTM
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

    init(_ set: ExerciseSet, id: SetAddress) {
        self.id = id
        index = set.index
        state = set.state.rawValue
        prescribedReps = set.prescribedReps
        prescribedLoad = set.prescribedLoad
        percentOneRM = set.percentOneRM
        setLog = set.setLog?.formatted
        unstructuredSetLog = set.unstructuredSetLog
        loggedAt = set.loggedAt
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

    init(_ exercise: Exercise, id: ExerciseAddress) {
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
            .map { SetSnapshot($0, id: SetAddress(exercise: id, index: $0.index)) }
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

    init(_ session: Session, id: SessionAddress, isCurrent: Bool) {
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
            .map { ExerciseSnapshot($0, id: ExerciseAddress(session: id, order: $0.order)) }
    }
}

/// The application at a glance: what is selected, how sync stands, and the Session index.
public struct AppSnapshot: Encodable, Equatable, Sendable {
    public let spreadsheetId: String?
    public let spreadsheetTitle: String?
    public let syncState: SyncStateSnapshot
    public let pendingWriteCount: Int
    public let block: BlockSummary?
    public let currentSession: SessionAddress?
    public let currentSessionReason: String
    public let currentSessionIsOverridden: Bool
    public let displayedSession: SessionAddress?
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
    public let syncState: SyncStateSnapshot
}

public struct SyncReport: Encodable, Equatable, Sendable {
    public let syncState: SyncStateSnapshot
    public let block: BlockSummary?
    public let currentSession: SessionAddress?
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

import Foundation
import SwiftData

/// Which Exercise of a Session a Set belongs to, as the Sheet addresses it: its Entered Name and
/// how many Exercises above it in the Session share that name. The name alone is not enough, because
/// a coach can name a top single and its back-off Sets both `Back Squat` (#813).
///
/// It is declared beside `PendingWrite`, the model that persists it, so its init and `ordinal` stay
/// fileprivate. Other code takes one from `Exercise.reference(in:)` or from a queued write.
struct ExerciseReference: Hashable, Sendable {
    let name: ExerciseName
    fileprivate let ordinal: Int

    /// The Exercise as a conflict names it: numbered past the first of its name, so a missing second
    /// `Back Squat` is not reported as a missing `Back Squat` while the first is still there.
    var label: String {
        ordinal == 0 ? name.entered : "\(name.entered) number \(ordinal + 1)"
    }

    /// The Exercise anchor this names in `day`, or nil when the Day holds fewer Exercises of its name.
    /// It agrees with `Exercise.reference(in:)` because BlockBuilder sets an Exercise's `order` to its
    /// anchor's index in the Day, so change the two together.
    func anchor(in day: SheetLayoutDay) -> SheetLayoutExerciseAnchor? {
        let sameNamed = day.exerciseAnchors.filter { $0.name == name.entered }
        return sameNamed.indices.contains(ordinal) ? sameNamed[ordinal] : nil
    }

    /// A reference no Sheet read backs, for fixtures and tests. The `exercise_references_are_parsed`
    /// lint rule bans it everywhere else.
    static func unchecked(name: ExerciseName, ordinal: Int) -> ExerciseReference {
        ExerciseReference(name: name, ordinal: ordinal)
    }
}

extension Exercise {
    /// Counts by `order`, the Sheet's top-to-bottom order, which the Sheet layout's Exercise anchors
    /// follow too.
    @MainActor
    func reference(in session: Session) -> ExerciseReference {
        ExerciseReference(
            name: exerciseName,
            ordinal: session.exercises.count { $0.exerciseName == exerciseName && $0.order < order }
        )
    }
}

enum DayNumbering: String, Sendable {
    case headerNumber
    case legacyHeaderRank

    init(stored raw: String?) {
        self = raw.flatMap(Self.init(rawValue:)) ?? .legacyHeaderRank
    }
}

enum PendingWriteColumn: String, Codable, Sendable {
    case notes
    case lastSetRPE
}

enum PendingWriteOperation: String, Codable, Sendable {
    case upsert
    case delete
}

enum PendingWriteStatus: String, Codable, Sendable {
    case pending
    case conflict
}

enum WriteTargetAuditStatus: String, Codable, Sendable {
    case succeeded
    case conflict
}

@Model
final class PendingWrite {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    // Shipped stores hold these attribute names.
    private var blockTab: String
    private var week: Int
    private var day: Int
    private var dayNumberingRaw: String?
    private var exerciseName: String
    // Nil on a write queued before #813, which named only the first Exercise of its name.
    private var exerciseOrdinalRaw: Int?
    var setIndex: Int
    var columnRaw: String
    var operationRaw: String
    var valueToWrite: String?
    var expectedCurrentValue: String
    var statusRaw: String
    var retryCount: Int
    var lastError: String?

    var exercise: ExerciseReference {
        ExerciseReference(name: ExerciseName(entered: exerciseName), ordinal: exerciseOrdinalRaw ?? 0)
    }

    var column: PendingWriteColumn {
        get { PendingWriteColumn(rawValue: columnRaw) ?? .notes }
        set { columnRaw = newValue.rawValue }
    }

    var operation: PendingWriteOperation {
        get { PendingWriteOperation(rawValue: operationRaw) ?? .upsert }
        set { operationRaw = newValue.rawValue }
    }

    var status: PendingWriteStatus {
        get { PendingWriteStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// When `dayNumbering` is `.legacyHeaderRank`, its Day is a header rank, so it names a Session
    /// only where `namesOneSession(on:)` holds.
    var recordedSession: SessionCoordinate {
        SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: week, day: day))
    }

    var dayNumbering: DayNumbering {
        DayNumbering(stored: dayNumberingRaw)
    }

    func namesOneSession(on layout: SheetLayout) -> Bool {
        switch dayNumbering {
        case .headerNumber: true
        case .legacyHeaderRank: layout.rankAndNumberAgree(week: week, rank: day)
        }
    }

    func overlays(on layout: SheetLayout) -> Bool {
        switch dayNumbering {
        case .headerNumber: namesOneSession(on: layout)
        case .legacyHeaderRank: namesOneSession(on: layout) && status == .pending
        }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        session: SessionCoordinate,
        dayNumbering: DayNumbering,
        exercise: ExerciseReference,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blockTab = session.blockTab
        self.week = session.address.week
        self.day = session.address.day
        self.dayNumberingRaw = dayNumbering.rawValue
        self.exerciseName = exercise.name.entered
        self.exerciseOrdinalRaw = exercise.ordinal
        self.setIndex = setIndex
        self.columnRaw = column.rawValue
        self.operationRaw = operation.rawValue
        self.valueToWrite = valueToWrite
        self.expectedCurrentValue = expectedCurrentValue
        self.statusRaw = PendingWriteStatus.pending.rawValue
        self.retryCount = 0
        self.lastError = nil
    }

    func markConflict(_ message: String) {
        status = .conflict
        lastError = message
    }
}

@Model
final class WriteTargetAuditEntry {
    static let limit = 100

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    // Shipped stores hold these attribute names.
    private var blockTab: String
    private var week: Int
    private var day: Int
    var exerciseName: String
    var setIndex: Int
    var columnRaw: String
    var selectedA1Target: String?
    var rowScanDetails: String
    var expectedCurrentValue: String
    var currentValue: String?
    var valueCheckOutcome: String
    var finalStatusRaw: String
    var message: String?

    var column: PendingWriteColumn {
        get { PendingWriteColumn(rawValue: columnRaw) ?? .notes }
        set { columnRaw = newValue.rawValue }
    }

    var finalStatus: WriteTargetAuditStatus {
        get { WriteTargetAuditStatus(rawValue: finalStatusRaw) ?? .conflict }
        set { finalStatusRaw = newValue.rawValue }
    }

    var recordedSession: SessionCoordinate {
        SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: week, day: day))
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        recordedSession: SessionCoordinate,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        selectedA1Target: String?,
        rowScanDetails: String,
        expectedCurrentValue: String,
        currentValue: String?,
        valueCheckOutcome: String,
        finalStatus: WriteTargetAuditStatus,
        message: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blockTab = recordedSession.blockTab
        self.week = recordedSession.address.week
        self.day = recordedSession.address.day
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.columnRaw = column.rawValue
        self.selectedA1Target = selectedA1Target
        self.rowScanDetails = rowScanDetails
        self.expectedCurrentValue = expectedCurrentValue
        self.currentValue = currentValue
        self.valueCheckOutcome = valueCheckOutcome
        self.finalStatusRaw = finalStatus.rawValue
        self.message = message
    }
}

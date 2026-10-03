import Foundation
import SwiftData

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
    // Shipped stores hold these attribute names. Read them through `session` and `dayNumbering`.
    private var blockTab: String
    private var week: Int
    private var day: Int
    private var dayNumberingRaw: String?
    var exerciseName: String
    var setIndex: Int
    var columnRaw: String
    var operationRaw: String
    var valueToWrite: String?
    var expectedCurrentValue: String
    var statusRaw: String
    var retryCount: Int
    var lastError: String?

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

    /// The Session as recorded at enqueue. Its Day reads per `dayNumbering`.
    var session: SessionCoordinate {
        SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: week, day: day))
    }

    var dayNumbering: DayNumbering {
        DayNumbering(stored: dayNumberingRaw)
    }

    func namesOneSession(on layout: SheetLayout) -> Bool {
        switch dayNumbering {
        case .headerNumber: true
        case .legacyHeaderRank: layout.rankAndNumberAgree(at: session.address)
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
        exerciseName: String,
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
        self.exerciseName = exerciseName
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
    // Shipped stores hold these attribute names. Read them through `session`.
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

    var session: SessionCoordinate {
        SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: week, day: day))
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        session: SessionCoordinate,
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
        self.blockTab = session.blockTab
        self.week = session.address.week
        self.day = session.address.day
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

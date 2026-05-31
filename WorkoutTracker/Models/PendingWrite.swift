import Foundation
import SwiftData

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
    var blockTab: String
    var week: Int
    var day: Int
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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        blockTab: String,
        week: Int,
        day: Int,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blockTab = blockTab
        self.week = week
        self.day = day
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
    var blockTab: String
    var week: Int
    var day: Int
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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        blockTab: String,
        week: Int,
        day: Int,
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
        self.blockTab = blockTab
        self.week = week
        self.day = day
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

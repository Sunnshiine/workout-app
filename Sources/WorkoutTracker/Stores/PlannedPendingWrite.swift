import Foundation

struct PlannedPendingWrite {
    let write: PendingWrite
    let cell: SheetCellWrite
    let snapshot: SheetWritePlanningSnapshot
    let auditDetails: SheetWriteAuditDetails

    /// Declared in the struct body so it replaces the memberwise init. A planned write is then built
    /// from one read only, so its target, value check, and audit row cannot disagree.
    @MainActor
    init(_ write: PendingWrite, against snapshot: SheetWritePlanningSnapshot, planner: SheetWritePlanner) throws {
        guard let request = SheetWriteRequest(write, on: snapshot.layout) else {
            throw PendingWritePlanningConflict(
                error: .dayHeadersChangedMeaning,
                refusedTarget: nil,
                auditDetails: .dayHeadersChangedMeaning(recorded: write.recordedSession.address)
            )
        }
        let target: SheetWriteTarget
        do {
            target = try planner.target(for: request, in: snapshot)
        } catch let error as SheetWriterError {
            throw PendingWritePlanningConflict(
                error: error,
                refusedTarget: nil,
                auditDetails: planner.auditDetails(for: request, error: error, in: snapshot, target: nil)
            )
        }
        do {
            cell = try planner.plan(request, target: target, in: snapshot)
        } catch let error as SheetWriterError {
            throw PendingWritePlanningConflict(
                error: error,
                refusedTarget: target,
                auditDetails: planner.auditDetails(for: request, error: error, in: snapshot, target: target)
            )
        }
        self.write = write
        self.snapshot = snapshot
        auditDetails = planner.auditDetails(for: request, target: target, in: snapshot)
    }
}

/// A Set Flag planned from one read, the way `PlannedPendingWrite` plans a value write. Only its
/// target can refuse it, since a flag checks no value.
struct PlannedSetFlagWrite {
    let write: PendingWrite
    let note: SheetCellNoteWrite
    let auditDetails: SheetWriteAuditDetails

    @MainActor
    init(_ write: PendingWrite, against snapshot: SheetWritePlanningSnapshot, planner: SheetWritePlanner) throws {
        guard let request = SheetWriteRequest(write, on: snapshot.layout) else {
            throw PendingWritePlanningConflict(
                error: .dayHeadersChangedMeaning,
                refusedTarget: nil,
                auditDetails: .dayHeadersChangedMeaning(recorded: write.recordedSession.address)
            )
        }
        do {
            let target = try planner.target(for: request, in: snapshot)
            note = planner.planSetFlag(request, target: target, in: snapshot)
            auditDetails = planner.auditDetails(for: request, target: target, in: snapshot)
        } catch let error as SheetWriterError {
            throw PendingWritePlanningConflict(
                error: error,
                refusedTarget: nil,
                auditDetails: planner.auditDetails(for: request, error: error, in: snapshot, target: nil)
            )
        }
        self.write = write
    }
}

struct PendingWritePlanningConflict: Error {
    let error: SheetWriterError
    let refusedTarget: SheetWriteTarget?
    let auditDetails: SheetWriteAuditDetails
}

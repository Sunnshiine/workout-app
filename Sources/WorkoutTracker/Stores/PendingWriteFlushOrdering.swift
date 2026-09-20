import Foundation

extension SyncCoordinator {
    func orderPendingWritesForFlush(_ pending: [PendingWrite]) -> [PendingWrite] {
        pending.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element

            if SetCoordinates.ID(left) == SetCoordinates.ID(right), left.column != right.column {
                return left.column == .notes
            }

            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }

            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func recordDependentLastSetRPEConflict(_ setLogConflict: String, for write: PendingWrite) -> String {
        let message = "Last Set RPE was not written because the paired Set Log failed: \(setLogConflict)"
        write.markConflict(message)
        recordWriteTargetAuditConflictWithoutPlanning(for: write, message: message)
        return "\(write.exerciseName): \(message)"
    }

    func recordDependentLastSetRPEConflicts(
        _ setLogConflict: String,
        for setLogWrite: PendingWrite,
        in pending: [PendingWrite]
    ) -> [String] {
        guard setLogWrite.column == .notes else { return [] }
        let key = SetCoordinates.ID(setLogWrite)
        return pending.compactMap { write in
            guard
                write.status == .pending,
                write.column == .lastSetRPE,
                SetCoordinates.ID(write) == key
            else { return nil }
            return recordDependentLastSetRPEConflict(setLogConflict, for: write)
        }
    }
}

import Foundation

struct PendingWriteSetLogKey: Hashable {
    let blockTab: String
    let week: Int
    let day: Int
    let exerciseName: String
    let setIndex: Int

    @MainActor
    init(_ write: PendingWrite) {
        self.blockTab = write.blockTab
        self.week = write.week
        self.day = write.day
        self.exerciseName = write.exerciseName
        self.setIndex = write.setIndex
    }
}

extension SyncCoordinator {
    func orderPendingWritesForFlush(_ pending: [PendingWrite]) -> [PendingWrite] {
        pending.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element

            if PendingWriteSetLogKey(left) == PendingWriteSetLogKey(right), left.column != right.column {
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
        return "\(write.exerciseName): \(message)"
    }

    func recordDependentLastSetRPEConflicts(
        _ setLogConflict: String,
        for setLogWrite: PendingWrite,
        in pending: [PendingWrite]
    ) -> [String] {
        guard setLogWrite.column == .notes else { return [] }
        let key = PendingWriteSetLogKey(setLogWrite)
        return pending.compactMap { write in
            guard
                write.status == .pending,
                write.column == .lastSetRPE,
                PendingWriteSetLogKey(write) == key
            else { return nil }
            return recordDependentLastSetRPEConflict(setLogConflict, for: write)
        }
    }
}

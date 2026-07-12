import Observation
import SwiftData

@MainActor
protocol LastPerformedLookupRefreshing {
    func refresh()
}

@MainActor
struct NoopLastPerformedLookupRefresher: LastPerformedLookupRefreshing {
    func refresh() {}
}

@MainActor
@Observable
final class LastPerformedLookupStore: LastPerformedLookupRefreshing, LastPerformedBackfillObserving {
    private(set) var snapshot: LastPerformedLookupSnapshot = .empty
    /// The most recent per-tab fill progress while the Exercise History fill is running, or `nil`
    /// once it has reached coverage or exhausted the tabs. The sheet renders its progress affordance
    /// from this (sub-issue #366) and drops it the moment the fill finishes.
    private(set) var fillProgress: LastPerformedBackfillProgress?
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    func refresh() {
        snapshot = LastPerformedIndex(context: context).snapshot()
    }

    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {
        fillProgress = progress
    }

    func lastPerformedBackfillDidFinish() {
        fillProgress = nil
    }
}

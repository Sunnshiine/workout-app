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
final class LastPerformedLookupStore: LastPerformedLookupRefreshing {
    private(set) var snapshot: LastPerformedLookupSnapshot = .empty
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    func refresh() {
        snapshot = LastPerformedIndex(context: context).snapshot()
    }
}

@MainActor
protocol LastPerformedBackfillObserving {
    func lastPerformedBackfillDidFinish()
}

@MainActor
struct NoopLastPerformedBackfillObserver: LastPerformedBackfillObserving {
    func lastPerformedBackfillDidFinish() {}
}

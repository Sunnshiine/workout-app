import Testing

@testable import WorkoutTracker

@MainActor
enum PollingLoopsAreBounded {
    static func whileLoopThatOnlyYieldsIsFlagged(store: SessionStore) async {
        while !store.isIdle {
            await Task.yield()
        }
    }

    static func repeatLoopThatOnlyYieldsIsFlagged(store: SessionStore) async {
        repeat {
            await Task.yield()
        } while !store.isIdle
    }

    static func countedLoopThatOnlyYieldsIsFlagged() async {
        for _ in 0..<100 { await Task.yield() }
    }

    static func conditionHoldingAClosurePasses(store: SessionStore) async {
        while !store.events.contains(where: { $0.isSync }) {
            await Task.yield()
        }
    }

    static func bodyThatDoesMorePasses(store: SessionStore) async {
        while !store.isIdle {
            store.tick()
            await Task.yield()
        }
    }

    static func boundedPollPasses(store: SessionStore) async {
        for _ in 0..<10_000 { if store.isIdle { return }; await Task.yield() }
        Issue.record("the store never went idle")
    }
}

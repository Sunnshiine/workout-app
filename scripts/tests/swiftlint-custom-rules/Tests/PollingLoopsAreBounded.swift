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

    static func whileLoopThatOnlyTriesAYieldIsFlagged(store: SessionStore) async throws {
        while !store.isIdle {
            try await Task.yield()
        }
    }

    static func conditionHoldingAClosureIsMissed(store: SessionStore) async {
        while !store.events.contains(where: { $0.isSync }) {
            await Task.yield()
        }
    }

    static func bodyThatDoesMoreIsMissed(store: SessionStore) async {
        while !store.isIdle {
            store.tick()
            await Task.yield()
        }
    }

    static func boundedPollPasses(store: SessionStore) async {
        for _ in 0..<10_000 { if store.isIdle { return }; await Task.yield() }
        Issue.record("the store never went idle")
    }

    static func yieldLoopInACommentPasses() {
        // while !store.isIdle { await Task.yield() }
    }

    static func yieldLoopInADocCommentPasses() {
        /// while !store.isIdle { await Task.yield() }
    }

    static func yieldLoopInAStringPasses() -> String {
        "while !store.isIdle { await Task.yield() }"
    }

    static func countedLoopWithANamedIndexIsMissed() async {
        for index in 0..<10 { await Task.yield() }
    }
}

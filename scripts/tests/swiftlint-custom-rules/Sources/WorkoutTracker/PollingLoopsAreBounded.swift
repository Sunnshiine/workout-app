@MainActor
enum PollingLoopsAreBounded {
    static func loopThatOnlyYieldsOutsideTestsPasses(store: SessionStore) async {
        while !store.isIdle {
            await Task.yield()
        }
    }
}

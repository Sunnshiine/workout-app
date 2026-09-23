import Testing

@testable import WorkoutTracker

@Test func bareTaskAtLineStartIsFlagged() async {
    let store = SessionStore.fixture()
    Task {
        await store.refresh()
    }
    #expect(store.isIdle)
}

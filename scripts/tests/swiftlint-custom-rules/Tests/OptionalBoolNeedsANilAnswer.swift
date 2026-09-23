import Testing

@testable import WorkoutTracker

@Test func optionalChainInAnExpectationPasses() {
    let session: Session? = nil
    #expect(session?.isComplete == true)
}

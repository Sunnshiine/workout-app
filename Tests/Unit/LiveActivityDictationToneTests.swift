import Testing

@testable import WorkoutTracker

/// Hosted only: the readback lives beside the Live Activity's attributes, which the app and the
/// widget compile and `swift test` does not.
@Suite
struct LiveActivityDictationToneTests {
    /// DESIGN.md, The Green Means Action Rule: the action greens are for progress that has actually
    /// happened, never decoration. The mic open and a Set Log are that; a skip, which the card draws
    /// muted, and a press that wrote nothing are not.
    @Test func onlyListeningAndASetLogTakeTheActionGreen() {
        let set = LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 1, setsTotal: 3)

        #expect(LiveActivityDictation.listening.tone == .action)
        #expect(LiveActivityDictation.logged("235×5 @7", to: set).tone == .action)
        #expect(LiveActivityDictation.skipped(set).tone == .quiet)
        #expect(LiveActivityDictation.notLogged("Nothing heard").tone == .quiet)
        #expect(LiveActivityDictation.noSetLeft(session: "Week 1 - Day 1").tone == .quiet)
        #expect(LiveActivityDictation.noCurrentSession.tone == .quiet)
    }
}

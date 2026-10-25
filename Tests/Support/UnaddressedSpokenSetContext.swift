@testable import WorkoutTracker

extension SpokenSetContext {
    /// What a Set no Block holds resolves against: a test about the write policy, not the record.
    init(draft: SetLogDraft, previous: SetLog?) {
        self.init(set: nil, draft: draft, previous: previous)
    }
}

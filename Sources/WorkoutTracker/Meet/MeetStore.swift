import Foundation
import Observation
import OSLog

private let meetStoreLogger = Logger(subsystem: "WorkoutTracker", category: "MeetStore")

/// The phone's one Meet, kept as JSON in `AppDefaults` and never sent to the Sheet.
@MainActor
@Observable
final class MeetStore {
    private(set) var record: MeetRecord?
    /// The Platform says so while it shows, and the root keeps the screen awake for it.
    var isPlatformOnScreen = false
    private let defaults: AppDefaults
    let now: @MainActor () -> Date
    private static let key = "meetRecord"

    init(defaults: AppDefaults, now: @escaping @MainActor () -> Date) {
        self.defaults = defaults
        self.now = now
        record = Self.load(defaults: defaults)
    }

    var meet: Meet? { record?.meet }
    var canUndoMark: Bool { record?.beforeLastMark != nil }

    func start(_ meet: Meet) {
        save(MeetRecord(meet: meet, beforeLastMark: nil))
    }

    func delete() {
        record = nil
        defaults.removeValue(forKey: Self.key)
    }

    /// A change to the Plan, which ends any chance to take back a mark.
    func edit(_ change: (inout Meet) -> Void) {
        guard var meet else { return }
        change(&meet)
        save(MeetRecord(meet: meet, beforeLastMark: nil))
    }

    func setAttemptsOut(_ count: Int) {
        edit { $0.setAttemptsOut(count) }
    }

    func mark(_ result: AttemptResult) throws(MeetRefusal) {
        try takeBackable { meet throws(MeetRefusal) in try meet.mark(result, at: now()) }
    }

    func pass() throws(MeetRefusal) {
        try takeBackable { meet throws(MeetRefusal) in try meet.pass() }
    }

    func submitNext(_ kilograms: Kilograms) throws(MeetRefusal) {
        try apply { meet throws(MeetRefusal) in try meet.submitNext(kilograms, at: now()) }
    }

    func acceptTableEntry() throws(MeetRefusal) {
        guard case .window(let window) = meet?.stage(at: now()) else { throw .noWindowOpen }
        try submitNext(window.tableEntry)
    }

    func changeOnDeck(to kilograms: Kilograms) throws(MeetRefusal) {
        try apply { meet throws(MeetRefusal) in try meet.changeOnDeck(to: kilograms, at: now()) }
    }

    func undoMark() {
        guard let before = record?.beforeLastMark else { return }
        save(MeetRecord(meet: before, beforeLastMark: nil))
    }

    private func takeBackable(_ gesture: (inout Meet) throws(MeetRefusal) -> Void) throws(MeetRefusal) {
        guard var meet else { throw .noAttemptOnDeck }
        let before = meet
        try gesture(&meet)
        save(MeetRecord(meet: meet, beforeLastMark: before))
    }

    private func apply(_ gesture: (inout Meet) throws(MeetRefusal) -> Void) throws(MeetRefusal) {
        guard var meet else { throw .noAttemptOnDeck }
        try gesture(&meet)
        save(MeetRecord(meet: meet, beforeLastMark: nil))
    }

    private func save(_ next: MeetRecord) {
        record = next
        do {
            let data = try JSONEncoder().encode(next)
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            defaults.set(text, forKey: Self.key)
        } catch {
            meetStoreLogger.error("Could not save the Meet: \(error)")
        }
    }

    private static func load(defaults: AppDefaults) -> MeetRecord? {
        guard let stored = defaults.string(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(MeetRecord.self, from: Data(stored.utf8))
        } catch {
            meetStoreLogger.error("Could not read the saved Meet: \(error)")
            return nil
        }
    }
}

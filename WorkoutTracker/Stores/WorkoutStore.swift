import Foundation
import SwiftData

@MainActor
@Observable
final class WorkoutStore {
    private(set) var block: Block?
    private(set) var displayedSession: Session?

    private let context: ModelContext
    private let tracker = SessionProgressTracker()

    init(context: ModelContext) { self.context = context }

    var currentSession: Session? { block.flatMap { tracker.currentSession(in: $0) } }
    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }

    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first
        displayedSession = currentSession
    }

    func show(week: Int, day: Int) {
        displayedSession = block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
    }
}

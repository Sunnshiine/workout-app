import Foundation

struct BlockOverviewTilePresentation: Equatable, Sendable {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState
    let accessibilityLabel: String
    let accessibilityIdentifier: String
}

struct BlockOverviewPresentation: Equatable, Sendable {
    let title: String
    let tiles: [BlockOverviewTilePresentation]

    @MainActor
    init(block: Block, currentSession: Session?) {
        title = block.tabName
        let tracker = SessionProgressTracker()
        tiles = block.weeks
            .sorted { $0.number < $1.number }
            .flatMap { week in
                week.sessions
                    .sorted { $0.dayNumber < $1.dayNumber }
                    .map { session in
                        let weekNumber = session.week?.number ?? week.number
                        return BlockOverviewTilePresentation(
                            weekNumber: weekNumber,
                            dayNumber: session.dayNumber,
                            state: tracker.tileState(for: session, currentSession: currentSession),
                            accessibilityLabel: "Week \(weekNumber), Day \(session.dayNumber)",
                            accessibilityIdentifier: "session-tile-W\(weekNumber)-D\(session.dayNumber)"
                        )
                    }
            }
    }
}

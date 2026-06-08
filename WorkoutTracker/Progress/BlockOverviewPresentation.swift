import Foundation

struct BlockOverviewTilePresentation: Equatable, Sendable {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
}

struct BlockOverviewPresentation: Equatable, Sendable {
    let title: String
    let tiles: [BlockOverviewTilePresentation]
    /// Number of grid columns — the Block's day width (widest Week), so each Week fills one
    /// row for 2–6 day programs instead of assuming 4 days per Week.
    let columnCount: Int

    @MainActor
    init(block: Block, currentSession: Session?) {
        title = block.tabName
        columnCount = max(block.weeks.map { $0.sessions.count }.max() ?? 4, 1)
        let tracker = SessionProgressTracker()
        tiles = block.weeks
            .sorted { $0.number < $1.number }
            .flatMap { week in
                week.sessions
                    .sorted { $0.dayNumber < $1.dayNumber }
                    .map { session in
                        let weekNumber = session.week?.number ?? week.number
                        let state = tracker.tileState(for: session, currentSession: currentSession)
                        return BlockOverviewTilePresentation(
                            weekNumber: weekNumber,
                            dayNumber: session.dayNumber,
                            state: state,
                            accessibilityLabel: "Week \(weekNumber), Day \(session.dayNumber)",
                            accessibilityValue: state.accessibilityValue,
                            accessibilityIdentifier: "session-tile-W\(weekNumber)-D\(session.dayNumber)"
                        )
                    }
            }
    }
}

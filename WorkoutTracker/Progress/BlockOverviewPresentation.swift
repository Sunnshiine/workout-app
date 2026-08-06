import Foundation

struct BlockOverviewTilePresentation: Equatable, Sendable {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState
    /// Ink rising from the tile's foot in quantized quarters (0...4), so partial work is
    /// visible without numbers (DESIGN.md §5.5). 0 is an empty foot (untouched or
    /// unavailable), 4 is full ink (complete); a partially settled Session lands in 1...3.
    let fillQuarters: Int
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
}

extension BlockOverviewTilePresentation {
    /// Quantize a Session's settled-Set fraction into foot-rising quarters (0...4).
    ///
    /// None settled → 0 (a quiet available tile, an empty foot); all settled → 4 (full
    /// ink). Any partial progress clamps to 1...3 so a barely-started Session still shows a
    /// quarter and an almost-finished one never reads as complete — partial ink is never
    /// mistaken for empty or full (DESIGN.md §5.5).
    static func fillQuarters(completed: Int, total: Int) -> Int {
        guard total > 0, completed > 0 else { return 0 }
        guard completed < total else { return 4 }
        let quarters = Int((Double(completed) / Double(total) * 4).rounded())
        return min(max(quarters, 1), 3)
    }
}

/// One Week's row in the Block grid. Exactly one Week — the one holding the Current
/// Session — is the focus, expanding into full tiles under morning light with the glowing
/// rim; every other Week collapses to a shaded card carrying a summary and a mini
/// day-strip (DESIGN.md §5.5).
struct BlockOverviewWeekPresentation: Equatable, Sendable {
    let weekNumber: Int
    /// The one Week that expands. The focus card alone earns the sunlit hour — the page's
    /// only delight.
    let isFocus: Bool
    /// The Week's day tiles, ordered available-first with Unavailable Sessions ("empty
    /// beds") grouped at the Week's end.
    let tiles: [BlockOverviewTilePresentation]
    /// The count clause, e.g. "2 of 3" — complete Sessions over the Week's day count. The
    /// focus card carries this alone; the tiles stay wordless.
    let summary: String
    /// The trailing state clause a collapsed card appends, e.g. "· 1 in progress" or
    /// "· 1 not uploaded". Empty when the Week is settled with nothing pending or missing.
    let detail: String

    /// The collapsed card's full one-line summary: the count plus any state clause.
    var collapsedSummary: String {
        detail.isEmpty ? summary : "\(summary) \(detail)"
    }
}

struct BlockOverviewPresentation: Equatable, Sendable {
    let title: String
    let weeks: [BlockOverviewWeekPresentation]
    /// Number of grid columns — the Block's day width (widest Week), so each Week fills one
    /// row for 2–6 day programs instead of assuming 4 days per Week.
    let columnCount: Int

    /// Every tile across all Weeks in week-then-tile order — the flattened view for callers
    /// that don't care about the focus-week grouping.
    var tiles: [BlockOverviewTilePresentation] {
        weeks.flatMap(\.tiles)
    }

    @MainActor
    init(block: Block, currentSession: Session?) {
        title = block.tabName
        columnCount = max(block.weeks.map { $0.sessions.count }.max() ?? 4, 1)
        let tracker = SessionProgressTracker()
        let orderedWeeks = block.weeks.sorted { $0.number < $1.number }

        // The focus Week holds the Current Session; with none derived (a brand-new Block),
        // the first Week expands so the grid is never fully collapsed.
        let focusWeekNumber: Int? = currentSession.flatMap { current in
            orderedWeeks.first { week in
                week.sessions.contains { $0.persistentModelID == current.persistentModelID }
            }?.number
        }
        let resolvedFocus = focusWeekNumber ?? orderedWeeks.first?.number

        weeks = orderedWeeks.map { week in
            let tiles = week.sessions
                .map { session in Self.tile(for: session, in: week, currentSession: currentSession, tracker: tracker) }
                // Empty beds group at the Week's end: available days first (by day), then
                // Unavailable Sessions (by day).
                .sorted { lhs, rhs in
                    let lhsEmpty = lhs.state == .unavailable
                    let rhsEmpty = rhs.state == .unavailable
                    if lhsEmpty != rhsEmpty { return !lhsEmpty }
                    return lhs.dayNumber < rhs.dayNumber
                }
            let dayCount = week.sessions.count
            let available = week.sessions.filter { tracker.isAvailable($0) }
            let complete = available.filter(\.isComplete).count
            let unavailable = dayCount - available.count
            let inProgress = available.filter { !$0.isComplete && $0.completedSetCount > 0 }.count
            return BlockOverviewWeekPresentation(
                weekNumber: week.number,
                isFocus: week.number == resolvedFocus,
                tiles: tiles,
                summary: "\(complete) of \(dayCount)",
                detail: Self.detail(unavailable: unavailable, inProgress: inProgress)
            )
        }
    }

    /// The trailing state clause. An un-uploaded day is the more urgent signal than an
    /// in-progress one, so it wins when both are present; a settled Week shows neither.
    private static func detail(unavailable: Int, inProgress: Int) -> String {
        if unavailable > 0 {
            return "· \(unavailable) not uploaded"
        }
        if inProgress > 0 {
            return "· \(inProgress) in progress"
        }
        return ""
    }

    @MainActor
    private static func tile(
        for session: Session,
        in week: Week,
        currentSession: Session?,
        tracker: SessionProgressTracker
    ) -> BlockOverviewTilePresentation {
        let weekNumber = session.week?.number ?? week.number
        let state = tracker.tileState(for: session, currentSession: currentSession)
        return BlockOverviewTilePresentation(
            weekNumber: weekNumber,
            dayNumber: session.dayNumber,
            state: state,
            fillQuarters: BlockOverviewTilePresentation.fillQuarters(
                completed: session.completedSetCount,
                total: session.totalSetCount
            ),
            accessibilityLabel: "Week \(weekNumber), Day \(session.dayNumber)",
            accessibilityValue: state.accessibilityValue,
            accessibilityIdentifier: "session-tile-W\(weekNumber)-D\(session.dayNumber)"
        )
    }
}

import SwiftUI

struct BlockOverviewView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.dismiss) private var dismiss

    let block: Block
    let currentSession: Session?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.sessionTileSpacing),
        count: 4
    )

    private var sessions: [Session] {
        block.weeks
            .sorted { $0.number < $1.number }
            .flatMap { week in
                week.sessions.sorted { $0.dayNumber < $1.dayNumber }
            }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.sessionTileSpacing) {
                ForEach(sessions, id: \.persistentModelID) { session in
                    Button {
                        show(session)
                    } label: {
                        SessionTile(
                            weekNumber: session.week?.number ?? 0,
                            dayNumber: session.dayNumber,
                            state: SessionProgressTracker().tileState(for: session, currentSession: currentSession)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week \(session.week?.number ?? 0), Day \(session.dayNumber)")
                    .accessibilityIdentifier(
                        "session-tile-W\(session.week?.number ?? 0)-D\(session.dayNumber)"
                    )
                }
            }
            .padding()
        }
        .background(Theme.gradient.ignoresSafeArea())
        .navigationTitle(block.tabName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func show(_ session: Session) {
        guard let week = session.week else { return }
        workout.show(week: week.number, day: session.dayNumber)
        dismiss()
    }
}

import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                if let session = workout.displayedSession {
                    List {
                        ForEach(session.exercises.sorted(by: { $0.order < $1.order }), id: \.persistentModelID) { ex in
                            Section {
                                if let note = ex.coachNote { Text(note).font(.callout).foregroundStyle(.secondary) }
                                ForEach(ex.sets.sorted(by: { $0.index < $1.index }), id: \.persistentModelID) { set in
                                    HStack {
                                        Text("Set \(set.index + 1)")
                                        Spacer()
                                        Text(set.prescribedReps).foregroundStyle(.secondary)
                                        Text(set.prescribedLoad).foregroundStyle(.secondary)
                                    }.font(.subheadline)
                                }
                            } header: {
                                Text(ex.cadence.map { "\($0)  " } ?? "") + Text(ex.baseName).bold()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No session yet",
                        systemImage: "dumbbell",
                        description: Text("Pull to refresh to sync your sheet.")
                    )
                }
            }
            .navigationTitle(breadcrumb)
            .refreshable {
                if let id = settings.spreadsheetId {
                    await sync.sync(spreadsheetId: id)
                    workout.reload()
                }
            }
            .task {
                workout.reload()
                if workout.block == nil, let id = settings.spreadsheetId {
                    await sync.sync(spreadsheetId: id)
                    workout.reload()
                }
            }
        }
    }

    private var breadcrumb: String {
        guard let s = workout.displayedSession else { return "Workout" }
        return "Block · W\(s.week?.number ?? 0) D\(s.dayNumber)"
    }
}

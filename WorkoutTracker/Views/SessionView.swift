import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                if let session = workout.displayedSession {
                    ScrollView {
                        GlassEffectContainer(spacing: Theme.cardSpacing) {
                            LazyVStack(spacing: Theme.cardSpacing) {
                                ForEach(
                                    session.exercises.sorted(by: { $0.order < $1.order }),
                                    id: \.persistentModelID
                                ) { exercise in
                                    ExerciseCard(exercise: exercise)
                                }
                            }
                            .padding()
                        }
                    }
                } else {
                    EmptyStateView {
                        if let id = settings.spreadsheetId {
                            await sync.sync(spreadsheetId: id)
                            workout.reload()
                        }
                    }
                }
            }
            .navigationTitle(breadcrumb)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(Theme.gradient.ignoresSafeArea())
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

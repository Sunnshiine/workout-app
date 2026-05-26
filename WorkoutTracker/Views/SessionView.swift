import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @State private var focusManager = ActiveSetFocusManager(session: nil)

    var body: some View {
        NavigationStack {
            Group {
                if let session = workout.displayedSession {
                    VStack(spacing: 0) {
                        SyncStatusBanner(state: sync.state)
                            .padding(.top, 8)

                        ScrollView {
                            GlassEffectContainer(spacing: Theme.cardSpacing) {
                                LazyVStack(spacing: Theme.cardSpacing) {
                                    SessionProgressHeader(session: session)

                                    ForEach(
                                        session.exercises.sorted(by: { $0.order < $1.order }),
                                        id: \.persistentModelID
                                    ) { exercise in
                                        ExerciseSection(
                                            exercise: exercise,
                                            activeSetID: focusManager.activeSetID,
                                            onFocus: { set in
                                                focusManager.focus(on: set)
                                            },
                                            onLog: { set, log in
                                                recordLog(set, as: log, in: session)
                                            },
                                            onSkip: { set in
                                                skip(set, in: session)
                                            },
                                            onDelete: { set in
                                                deleteLog(for: set)
                                            }
                                        )
                                    }
                                }
                                .padding()
                            }
                        }
                        .task(id: session.persistentModelID) {
                            focusManager.reset(to: session)
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

    private func recordLog(_ set: ExerciseSet, as log: SetLog, in session: Session) {
        do {
            try workout.log(set, as: log)
            focusManager.advanceAfterLog(set, in: session)
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func skip(_ set: ExerciseSet, in session: Session) {
        do {
            try workout.skip(set)
            focusManager.advanceAfterSkip(set, in: session)
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func deleteLog(for set: ExerciseSet) {
        do {
            try workout.deleteLog(for: set)
            focusManager.focus(on: set)
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func flushPendingWrites() {
        guard let id = settings.spreadsheetId else { return }
        Task { await sync.flushPending(spreadsheetId: id) }
    }
}

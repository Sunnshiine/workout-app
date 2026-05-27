import SwiftData
import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var focusManager = ActiveSetFocusManager(session: nil)
    @State private var retiringTransition: ActiveSetTransition?

    var body: some View {
        Group {
            if let session = workout.displayedSession {
                VStack(spacing: 0) {
                    SyncStatusBanner(state: sync.state)
                        .padding(.top, 8)

                    ScrollView {
                        GlassEffectContainer(spacing: Theme.cardSpacing) {
                            LazyVStack(alignment: .leading, spacing: Theme.cardSpacing) {
                                SessionProgressHeader(session: session)

                                ForEach(
                                    session.exercises.sorted(by: { $0.order < $1.order }),
                                    id: \.persistentModelID
                                ) { exercise in
                                    ExerciseSection(
                                        exercise: exercise,
                                        lastPerformedIndex: LastPerformedIndex(context: modelContext),
                                        activeSetID: focusManager.activeSetID,
                                        activeSetTransition: focusManager.activeSetTransition,
                                        retiringTransition: retiringTransition,
                                        isCollapsed: focusManager.isCollapsed(exercise),
                                        onFocus: { set in
                                            focusManager.focus(on: set)
                                        },
                                        onReexpand: {
                                            focusManager.reexpand(exercise)
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
                        }
                        .padding(.horizontal)
                        .padding(.vertical)
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let session = workout.displayedSession, let block = workout.block {
                    NavigationLink {
                        BlockOverviewView(block: block, currentSession: workout.currentSession)
                    } label: {
                        HStack(spacing: 5) {
                            Text(SessionProgressHeaderPresentation(session: session).breadcrumb)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func recordLog(_ set: ExerciseSet, as log: SetLog, in session: Session) {
        do {
            try workout.log(set, as: log)
            withAnimation(Theme.momentumFlowAnimation) {
                focusManager.advanceAfterLog(set, in: session)
            }
            retireActiveSetTransition()
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func skip(_ set: ExerciseSet, in session: Session) {
        do {
            try workout.skip(set)
            withAnimation(Theme.skipFadeUpAnimation) {
                focusManager.advanceAfterSkip(set, in: session)
            }
            retireActiveSetTransition()
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func deleteLog(for set: ExerciseSet) {
        do {
            try workout.deleteLog(for: set)
            focusManager.focus(on: set)
            retiringTransition = nil
            flushPendingWrites()
        } catch {
            sync.reportLocalWriteFailure(error)
        }
    }

    private func flushPendingWrites() {
        guard let id = settings.spreadsheetId else { return }
        Task { await sync.flushPending(spreadsheetId: id) }
    }

    private func retireActiveSetTransition() {
        guard let transition = focusManager.activeSetTransition else { return }
        retiringTransition = transition
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: transitionClearDelay(for: transition))
            guard retiringTransition == transition else { return }
            retiringTransition = nil
            focusManager.clearTransition(transition)
        }
    }

    private func transitionClearDelay(for transition: ActiveSetTransition) -> UInt64 {
        let duration =
            switch transition.kind {
            case .momentumFlow:
                Theme.momentumFlowTotalDuration
            case .softFadeUp:
                Theme.skipFadeUpDuration
            case .collapseAndRise:
                Theme.momentumDropDuration
                    + Theme.exerciseCompletionBeatDuration
                    + Theme.momentumRiseDuration
            }
        return UInt64(duration * 1_000_000_000)
    }
}

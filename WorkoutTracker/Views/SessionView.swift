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

                    if !workout.isViewingLiveEdge {
                        BackToCurrentSessionBanner {
                            workout.showCurrent()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    SessionProgressHeader(
                        session: session,
                        activeSetID: focusManager.activeSetID,
                        block: workout.block,
                        currentSession: workout.currentSession
                    )
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollView {
                        GlassEffectContainer(spacing: Theme.cardSpacing) {
                            LazyVStack(alignment: .leading, spacing: Theme.cardSpacing) {
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

                                if workout.isViewingLiveEdge, !workout.openExercises.isEmpty {
                                    OpenExercisesSection(
                                        exercises: workout.openExercises,
                                        onSelect: showSourceSession(for:)
                                    )
                                }

                                if workout.isViewingLiveEdge, workout.canMoveOn {
                                    MoveOnButton {
                                        workout.moveOn()
                                    }
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

    private func showSourceSession(for exercise: Exercise) {
        guard let session = exercise.session, let week = session.week else { return }
        workout.show(week: week.number, day: session.dayNumber)
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

private struct BackToCurrentSessionBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left")
                    .font(.subheadline.weight(.semibold))
                Text("Back to Current Session")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.accentDarkText)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Returns to the current session")
    }
}

private struct MoveOnButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Move On", systemImage: "arrow.right")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Advances to the next session")
    }
}

private struct OpenExercisesSection: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Exercises")
                .font(.headline)

            ForEach(exercises, id: \.persistentModelID) { exercise in
                Button {
                    onSelect(exercise)
                } label: {
                    OpenExerciseCard(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

private struct OpenExerciseCard: View {
    let exercise: Exercise

    private var pendingSetCount: Int {
        exercise.sets.filter { $0.state == .pending }.count
    }

    private var sourceLabel: String {
        guard let session = exercise.session, let week = session.week else { return "" }
        return "W\(week.number) D\(session.dayNumber)"
    }

    private var pendingSetLabel: String {
        pendingSetCount == 1 ? "1 pending set" : "\(pendingSetCount) pending sets"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.baseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(pendingSetLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(sourceLabel)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .stroke(Theme.pillStroke, lineWidth: 1)
        }
    }
}

import SwiftData
import SwiftUI
import UIKit

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = SessionCoordinator(session: nil)

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
                        activeSetID: coordinator.activeSetID,
                        block: workout.block,
                        currentSession: workout.currentSession,
                        onNavigate: coordinator.cancelPairing
                    )
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollViewReader { proxy in
                        ScrollView {
                            GlassEffectContainer(spacing: Theme.cardSpacing) {
                                LazyVStack(alignment: .leading, spacing: Theme.cardSpacing) {
                                    let supersetSections = coordinator.supersetSections(in: session)
                                    let supersetByContainer = Dictionary(
                                        uniqueKeysWithValues: supersetSections.compactMap { section in
                                            section.presentation.containerExerciseOrder.map { ($0, section) }
                                        }
                                    )
                                    let exerciseRenderItemsByOrder = Dictionary(
                                        uniqueKeysWithValues: coordinator.exerciseRenderItems(
                                            in: session
                                        ).map { ($0.exercise.order, $0) }
                                    )

                                    ForEach(
                                        session.exercises.sorted(by: { $0.order < $1.order }),
                                        id: \.persistentModelID
                                    ) { exercise in
                                        if let supersetSection = supersetByContainer[exercise.order] {
                                            ActiveSupersetSection(
                                                presentation: supersetSection.presentation,
                                                exercises: supersetSection.exercises,
                                                lastPerformedIndex: LastPerformedIndex(context: modelContext),
                                                activeSetTransition: coordinator.activeSetTransition,
                                                retiringTransition: coordinator.retiringTransition,
                                                onFocusExercise: { focusedExercise in
                                                    coordinator.focusNextSupersetSet(for: focusedExercise, in: session)
                                                },
                                                onLog: { set, log in
                                                    coordinator.log(set, as: log) { updateFocus in
                                                        withAnimation(Theme.momentumFlowAnimation) {
                                                            updateFocus()
                                                        }
                                                    }
                                                },
                                                onSkip: { set in
                                                    coordinator.skip(set) { updateFocus in
                                                        withAnimation(Theme.skipFadeUpAnimation) {
                                                            updateFocus()
                                                        }
                                                    }
                                                },
                                                onDelete: { set in
                                                    coordinator.deleteLog(for: set)
                                                },
                                                onDismiss: {
                                                    guard let exercise = supersetSection.exercises.first else { return }
                                                    withAnimation(Theme.momentumFlowAnimation) {
                                                        coordinator.dismissSuperset(containing: exercise, in: session)
                                                    }
                                                }
                                            )
                                            .id(supersetSurfaceID(for: supersetSection.presentation))
                                        } else if let renderItem = exerciseRenderItemsByOrder[exercise.order] {
                                            ExerciseSection(
                                                exercise: renderItem.exercise,
                                                lastPerformedIndex: LastPerformedIndex(context: modelContext),
                                                activeSetID: renderItem.activeSetID,
                                                activeSetTransition: renderItem.activeSetTransition,
                                                retiringTransition: coordinator.retiringTransition,
                                                isCollapsed: renderItem.isCollapsed,
                                                showsPairingGrip: renderItem.showsPairingGrip,
                                                pairingAvailability: renderItem.pairingAvailability,
                                                isPairingConfirmation: renderItem.isPairingConfirmation,
                                                onFocus: { set in
                                                    coordinator.focus(on: set)
                                                },
                                                onReexpand: {
                                                    coordinator.reexpand(renderItem.exercise)
                                                },
                                                onLog: { set, log in
                                                    coordinator.log(set, as: log) { updateFocus in
                                                        withAnimation(Theme.momentumFlowAnimation) {
                                                            updateFocus()
                                                        }
                                                    }
                                                },
                                                onSkip: { set in
                                                    coordinator.skip(set) { updateFocus in
                                                        withAnimation(Theme.skipFadeUpAnimation) {
                                                            updateFocus()
                                                        }
                                                    }
                                                },
                                                onDelete: { set in
                                                    coordinator.deleteLog(for: set)
                                                },
                                                onBeginPairing: {
                                                    coordinator.beginPairing(from: renderItem.exercise, in: session)
                                                },
                                                onPairingTap: {
                                                    if coordinator.handlePairingTap(on: renderItem.exercise, in: session) == .unavailable {
                                                        warningHaptic()
                                                    }
                                                }
                                            )
                                        }
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

                                    Color.clear
                                        .frame(height: 44)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: coordinator.cancelPairing)
                                }
                                .background {
                                    if coordinator.pairingMode != .inactive {
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .onTapGesture(perform: coordinator.cancelPairing)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical)
                        }
                        .onChange(of: coordinator.scrollTargetID) { _, targetID in
                            scrollToSet(targetID, with: proxy)
                        }
                        .onChange(of: coordinator.supersetScrollTargetOrder) { _, order in
                            scrollToSuperset(order, with: proxy)
                        }
                    }
                    .onAppear {
                        bindCoordinator(to: session)
                    }
                    .onChange(of: session.persistentModelID) { _, _ in
                        bindCoordinator(to: session)
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

    private func bindCoordinator(to session: Session) {
        coordinator.bind(
            to: session,
            logging: workout,
            sync: SessionPendingWriteSyncAdapter(sync: sync, settings: settings)
        )
    }

    private func showSourceSession(for exercise: Exercise) {
        coordinator.cancelPairing()
        guard let session = exercise.session, let week = session.week else { return }
        workout.show(week: week.number, day: session.dayNumber)
    }

    private func scrollToSet(_ targetID: ActiveSetID?, with proxy: ScrollViewProxy) {
        guard let targetID else { return }
        withAnimation(Theme.momentumFlowAnimation) {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }

    private func scrollToSuperset(_ order: Int?, with proxy: ScrollViewProxy) {
        guard let order else { return }
        withAnimation(Theme.momentumFlowAnimation) {
            proxy.scrollTo(supersetSurfaceID(for: order), anchor: .center)
        }
    }

    private func supersetSurfaceID(for presentation: ActiveSupersetPresentation) -> String {
        supersetSurfaceID(for: presentation.containerExerciseOrder ?? Int.min)
    }

    private func supersetSurfaceID(for order: Int) -> String {
        "superset-\(order)"
    }
}

extension SessionView {
    fileprivate func warningHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        .accessibilityIdentifier("back-to-current-session-button")
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
        .accessibilityIdentifier("move-on-button")
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

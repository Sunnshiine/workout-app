import SwiftUI
import UIKit

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coordinator = SessionCoordinator(session: nil)
    @State private var sessionControlsVisibility = SessionControlsVisibility.hidden
    @State private var isSettingsPresented = false
    @State private var isSessionControlsSyncInFlight = false

    var body: some View {
        Group {
            if let session = workout.displayedSession {
                VStack(spacing: 0) {
                    SyncStatusBanner(state: sync.state)
                        .padding(.top, 8)

                    if !workout.isViewingLiveEdge {
                        CurrentSessionOverrideControls(
                            onGoBack: {
                                workout.showCurrent()
                            },
                            onMakeCurrent: {
                                workout.makeDisplayedSessionCurrent()
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    SessionProgressHeader(
                        session: session,
                        activeSetID: coordinator.activeSetID,
                        block: workout.block,
                        currentSession: workout.currentSession,
                        showsSessionControls: shouldShowSessionControls,
                        isSessionControlsSyncDisabled: isSessionControlsSyncDisabled,
                        onNavigate: coordinator.cancelPairing,
                        onSettings: {
                            isSettingsPresented = true
                        },
                        onSync: {
                            Task { await syncConfiguredSheet() }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 12)

                    ScrollViewReader { proxy in
                        ScrollView {
                            GlassEffectContainer(spacing: Theme.cardSpacing) {
                                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                                    ForEach(
                                        coordinator.renderItems(
                                            in: session,
                                            lastPerformedLookup: lastPerformedLookup.snapshot
                                        ),
                                        id: \.id
                                    ) { item in
                                        renderItem(item, in: session)
                                    }

                                    if workout.isViewingLiveEdge, !workout.openExercises.isEmpty {
                                        OpenExercisesSection(
                                            exercises: workout.openExercises,
                                            onSelect: showSourceSession(for:)
                                        )
                                    }

                                    if workout.isViewingLiveEdge, workout.canMoveOn {
                                        MoveOnButton {
                                            workout.requestMoveOnCelebration()
                                        }
                                    }

                                    Color.clear
                                        .frame(height: 44)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            coordinator.cancelPairing()
                                            coordinator.collapseLoggedSetReview()
                                        }
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
                        .scrollBounceBehavior(.always)
                        .onScrollGeometryChange(for: CGFloat.self, of: topContentOffset) { _, offset in
                            updateSessionControls(topContentOffset: offset)
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
                ScrollView {
                    EmptyStateView {
                        await syncConfiguredSheet()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 80)
                }
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: CGFloat.self, of: topContentOffset) { _, offset in
                    updateSessionControls(topContentOffset: offset)
                }
            }
        }
        .accessibilityHidden(workout.moveOnCelebrationSession != nil)
        .background(Theme.gradient.ignoresSafeArea())
        .overlay {
            if let session = workout.moveOnCelebrationSession {
                MoveOnCelebrationView(session: session) {
                    workout.dismissMoveOnCelebration()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: sessionControlsVisibility.isVisible)
        .animation(.easeInOut(duration: 0.18), value: workout.moveOnCelebrationSession?.persistentModelID)
        .navigationDestination(isPresented: blockOverviewRequestBinding) {
            if let block = workout.block {
                BlockOverviewView(block: block, currentSession: workout.currentSession)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .task {
            workout.reload()
            if workout.block == nil, let id = settings.spreadsheetId {
                await sync.sync(spreadsheetId: id)
                workout.reload()
            }
        }
    }

    private func updateSessionControls(topContentOffset: CGFloat) {
        let updatedVisibility = sessionControlsVisibility.updated(topContentOffset: topContentOffset)
        guard updatedVisibility != sessionControlsVisibility else { return }
        sessionControlsVisibility = updatedVisibility
    }

    private func topContentOffset(_ geometry: ScrollGeometry) -> CGFloat {
        -(geometry.contentOffset.y + geometry.contentInsets.top)
    }

    private var isSessionControlsSyncDisabled: Bool {
        isSessionControlsSyncInFlight || sync.state == .syncing
    }

    private var shouldShowSessionControls: Bool {
        sessionControlsVisibility.isVisible && workout.moveOnCelebrationSession == nil
    }

    private var blockOverviewRequestBinding: Binding<Bool> {
        Binding {
            workout.pendingBlockOverviewRequest != nil
        } set: { isPresented in
            if !isPresented {
                workout.clearBlockOverviewRequest()
            }
        }
    }

    @MainActor
    private func syncConfiguredSheet() async {
        guard let id = settings.spreadsheetId, !isSessionControlsSyncDisabled else { return }
        isSessionControlsSyncInFlight = true
        defer { isSessionControlsSyncInFlight = false }
        await sync.sync(spreadsheetId: id)
        workout.reload()
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

    @ViewBuilder
    private func renderItem(_ item: SessionRenderItem, in session: Session) -> some View {
        switch item {
        case .exercise(let config):
            ExerciseSection(
                config: config,
                onFocus: focusWithMorph,
                onReexpand: {
                    coordinator.reexpand(config.exercise)
                },
                onLog: logWithMomentum,
                onUpdateLoggedSet: coordinator.updateLoggedSet(_:as:),
                onSkip: skipWithFade,
                onDelete: coordinator.deleteLog(for:),
                onBeginPairing: {
                    coordinator.beginPairing(from: config.exercise, in: session)
                },
                onPairingTap: {
                    handlePairingTap(on: config.exercise, in: session)
                }
            )
        case .superset(let config):
            ActiveSupersetSection(
                config: config,
                onFocusExercise: { focusedExercise in
                    coordinator.focusNextSupersetSet(for: focusedExercise, in: session)
                },
                onLog: logWithMomentum,
                onSkip: skipWithFade,
                onDelete: coordinator.deleteLog(for:),
                onDismiss: {
                    dismissSuperset(config, in: session)
                }
            )
            .id(supersetSurfaceID(for: config.presentation))
        case .hiddenPairedExercise:
            EmptyView()
        }
    }

    private func focusWithMorph(_ set: ExerciseSet) {
        guard set.state == .pending, !reduceMotion else {
            coordinator.focus(on: set)
            return
        }

        coordinator.focus(on: set) { updateFocus in
            withAnimation(Theme.focusMorphAnimation) {
                updateFocus()
            }
        }
    }

    private func logWithMomentum(_ set: ExerciseSet, _ log: SetLog) {
        coordinator.log(set, as: log) { updateFocus in
            withAnimation(Theme.momentumFlowAnimation) {
                updateFocus()
            }
        }
    }

    private func skipWithFade(_ set: ExerciseSet) {
        coordinator.skip(set) { updateFocus in
            withAnimation(Theme.skipFadeUpAnimation) {
                updateFocus()
            }
        }
    }

    private func dismissSuperset(_ config: SessionSupersetRenderConfig, in session: Session) {
        guard let exercise = config.exercises.first else { return }
        withAnimation(Theme.momentumFlowAnimation) {
            coordinator.dismissSuperset(containing: exercise, in: session)
        }
    }

    private func handlePairingTap(on exercise: Exercise, in session: Session) {
        if coordinator.handlePairingTap(on: exercise, in: session) == .unavailable {
            warningHaptic()
        }
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

private struct CurrentSessionOverrideControls: View {
    let onGoBack: () -> Void
    let onMakeCurrent: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                goBackButton
                makeCurrentButton
            }

            VStack(spacing: 10) {
                goBackButton
                makeCurrentButton
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var goBackButton: some View {
        Button(action: onGoBack) {
            Label("Go back", systemImage: "arrow.uturn.left")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Returns to the current session")
        .accessibilityIdentifier("go-back-current-session-button")
    }

    private var makeCurrentButton: some View {
        Button(action: onMakeCurrent) {
            Label("Make Current", systemImage: "pin.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Makes the viewed session the current session")
        .accessibilityIdentifier("make-current-session-button")
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

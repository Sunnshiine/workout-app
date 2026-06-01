import SwiftUI
import UIKit

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @State private var coordinator = SessionCoordinator(session: nil)
    @State private var sessionAllClearRevision = 0
    @State private var sessionSettingsOverpullState = SessionSettingsOverpullState.hidden
    @State private var sessionSettingsOverpullDismissalID = 0
    @State private var isSettingsPresented = false

    var body: some View {
        Group {
            if let session = workout.displayedSession {
                VStack(spacing: 0) {
                    SyncStatusBanner(state: sync.state)
                        .padding(.top, 8)

                    if !workout.isViewingLiveEdge {
                        CurrentSessionOverrideControls(
                            onGoBack: {
                                sessionSettingsOverpullState = .hidden
                                workout.showCurrent()
                            },
                            onMakeCurrent: {
                                sessionSettingsOverpullState = .hidden
                                workout.makeDisplayedSessionCurrent()
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                GlassEffectContainer(spacing: Theme.cardSpacing) {
                                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
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
                                            .onTapGesture(perform: clearTransientSessionUI)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(inertSessionTapArea)
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(inertSessionTapArea)
                            .padding(.vertical)
                        }
                        .scrollBounceBehavior(.always)
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            sessionHeaderHUD(session: session)
                        }
                        .onScrollGeometryChange(for: CGFloat.self, of: topContentOffset) { _, offset in
                            updateSessionSettingsOverpull(topContentOffset: offset)
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
                        isSettingsPresented = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 80)
                }
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: CGFloat.self, of: topContentOffset) { _, offset in
                    updateSessionSettingsOverpull(topContentOffset: offset)
                }
            }
        }
        .accessibilityHidden(workout.moveOnCelebrationSession != nil)
        .environment(\.sessionAllClearRevision, sessionAllClearRevision)
        .background(palette.gradient.ignoresSafeArea())
        .overlay {
            if let session = workout.moveOnCelebrationSession {
                MoveOnCelebrationView(session: session) {
                    workout.dismissMoveOnCelebration()
                }
                .transition(.opacity)
            }
        }
        .animation(sessionSettingsOverpullAnimation, value: sessionSettingsOverpullState)
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
        .task(id: sessionSettingsOverpullDismissalID) {
            guard sessionSettingsOverpullState.isPinned else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(SessionSettingsOverpullState.idleDismissDelay * 1_000_000_000)
            )
            guard !Task.isCancelled, sessionSettingsOverpullState.isPinned else { return }
            sessionSettingsOverpullState = sessionSettingsOverpullState.dismissedAfterIdle()
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

    private func clearTransientSessionUI() {
        sessionSettingsOverpullState = sessionSettingsOverpullState.dismissedByInertAllClearTap()
        sessionAllClearRevision += 1
        coordinator.clearTransientUI()
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
                    focusSupersetWithMorph(focusedExercise, in: session)
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
        let action = focusMorphAction(for: set)
        let policy = SessionFocusMorphPolicy(reduceMotion: reduceMotion)
        guard policy.shouldAnimate(action) else {
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
    private func updateSessionSettingsOverpull(topContentOffset: CGFloat) {
        guard canRevealSessionControls else {
            if sessionSettingsOverpullState != .hidden {
                sessionSettingsOverpullState = .hidden
            }
            return
        }

        applySessionSettingsOverpullState(
            sessionSettingsOverpullState.trackingScroll(topContentOffset: topContentOffset)
        )
    }

    private var sessionSettingsHeaderPullGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                updateSessionSettingsHeaderPull(translationHeight: value.translation.height)
            }
            .onEnded { value in
                releaseSessionSettingsHeaderPull(translationHeight: value.translation.height)
            }
    }

    private func updateSessionSettingsHeaderPull(translationHeight: CGFloat) {
        guard canRevealSessionControls else {
            if sessionSettingsOverpullState != .hidden {
                sessionSettingsOverpullState = .hidden
            }
            return
        }

        guard translationHeight >= 0 else {
            applySessionSettingsOverpullState(.hidden)
            return
        }

        applySessionSettingsOverpullState(
            sessionSettingsOverpullState.tracking(topContentOffset: translationHeight)
        )
    }

    private func releaseSessionSettingsHeaderPull(translationHeight: CGFloat) {
        guard canRevealSessionControls else { return }

        applySessionSettingsOverpullState(
            sessionSettingsOverpullState.released(topContentOffset: translationHeight)
        )
    }

    private func applySessionSettingsOverpullState(_ state: SessionSettingsOverpullState) {
        guard state != sessionSettingsOverpullState else { return }
        let startsPinned = state.isPinned && !sessionSettingsOverpullState.isPinned
        sessionSettingsOverpullState = state
        if startsPinned {
            sessionSettingsOverpullDismissalID += 1
        }
    }

    /// The W1D1 · N-left · progress-rail header, floated as an inset Liquid Glass
    /// HUD pinned to the top. Content scrolls beneath it; over-pulling past the
    /// reveal threshold morphs it open to expose Settings on top.
    @ViewBuilder
    private func sessionHeaderHUD(session: Session) -> some View {
        SessionProgressHeader(
            session: session,
            activeSetID: coordinator.activeSetID,
            block: workout.block,
            currentSession: workout.currentSession,
            sessionSettingsOverpullState: sessionSettingsOverpullState,
            onNavigate: coordinator.cancelPairing,
            onSettings: {
                sessionSettingsOverpullState = .hidden
                isSettingsPresented = true
            }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .padding(.horizontal)
        .padding(.top, 8)
        .highPriorityGesture(sessionSettingsHeaderPullGesture)
    }

    private func topContentOffset(_ geometry: ScrollGeometry) -> CGFloat {
        -(geometry.contentOffset.y + geometry.contentInsets.top)
    }

    private var canRevealSessionControls: Bool {
        workout.displayedSession != nil && workout.isViewingLiveEdge && workout.moveOnCelebrationSession == nil
    }

    private var sessionSettingsOverpullAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22)
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

    private func focusMorphAction(for set: ExerciseSet) -> SessionFocusMorphAction {
        guard set.state == .logged else {
            return set.state == .pending ? .pendingFocus : .loggedReviewCollapse
        }
        let setID = SessionCoordinator.activeSetID(for: set)
        return setID == coordinator.expandedLoggedSetID ? .loggedReviewCollapse : .loggedReviewOpen
    }

    private func focusSupersetWithMorph(_ exercise: Exercise, in session: Session) {
        let policy = SessionFocusMorphPolicy(reduceMotion: reduceMotion)
        guard policy.shouldAnimate(.supersetSwitchSucceeded) else {
            _ = coordinator.focusNextSupersetSet(for: exercise, in: session)
            return
        }

        _ = coordinator.focusNextSupersetSet(for: exercise, in: session) { updateFocus in
            withAnimation(Theme.focusMorphAnimation) {
                updateFocus()
            }
        }
    }

    fileprivate func warningHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private var inertSessionTapArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: clearTransientSessionUI)
    }
}

private struct SessionAllClearRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var sessionAllClearRevision: Int {
        get { self[SessionAllClearRevisionKey.self] }
        set { self[SessionAllClearRevisionKey.self] = newValue }
    }
}

private struct CurrentSessionOverrideControls: View {
    let onGoBack: () -> Void
    let onMakeCurrent: () -> Void

    var body: some View {
        HStack {
            goBackButton
            Spacer(minLength: 0)
            makeCurrentButton
        }
        .accessibilityElement(children: .contain)
    }

    private var goBackButton: some View {
        Button(action: onGoBack) {
            Label("Go back", systemImage: "arrow.uturn.left")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Returns to the current session")
        .accessibilityIdentifier("go-back-current-session-button")
    }

    private var makeCurrentButton: some View {
        Button(action: onMakeCurrent) {
            Label("Make Current", systemImage: "pin.fill")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
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
    @Environment(\.themePalette) private var palette

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
            .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .stroke(palette.pillStroke, lineWidth: 1)
        }
    }
}

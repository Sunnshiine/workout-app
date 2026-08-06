import SwiftUI
import UIKit

struct SessionView: View {
    let liveActivityAdapter: LiveActivityProductionAdapter
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @State private var coordinator = SessionCoordinator(session: nil)
    #if canImport(UserNotifications)
        @State private var restTimer = RestTimer(notificationScheduler: RestNotificationCenterScheduler.shared)
    #else
        @State private var restTimer = RestTimer()
    #endif
    @State private var sessionSettingsOverpullState = SessionSettingsOverpullState.hidden
    @State private var sessionSettingsOverpullDismissalID = 0
    @State private var sessionSettingsTopContentOffset: CGFloat = 0
    @State private var sessionSettingsDragStartTopContentOffset: CGFloat?
    @State private var isSettingsPresented = false

    init(liveActivityAdapter: LiveActivityProductionAdapter = LiveActivityProductionAdapter()) {
        self.liveActivityAdapter = liveActivityAdapter
    }

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

                    productionStage(for: session)
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
        .background(palette.paperBackground.ignoresSafeArea())
        // Tap-anywhere keyboard escape: a tap on the session surface that no control claims
        // resigns the first responder, so the athlete never hunts for the one dismissing
        // region. Buttons, rails, and the weight field still win the tap — this only
        // catches what falls through.
        .contentShape(.rect)
        .onTapGesture(perform: dismissAnyKeyboard)
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
            reconcileLiveActivity()
            if workout.block == nil, let id = settings.spreadsheetId {
                await sync.sync(spreadsheetId: id)
                workout.reload()
                reconcileLiveActivity()
            }
        }
        .onChange(of: workout.block?.persistentModelID) { _, _ in
            reconcileLiveActivity()
        }
        .onChange(of: workout.currentSession?.persistentModelID) { _, _ in
            reconcileLiveActivity()
        }
        .onChange(of: workout.displayedSession?.persistentModelID) { _, _ in
            reconcileLiveActivity()
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

    private func dismissAnyKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private func bindCoordinator(to session: Session) {
        coordinator.bind(
            to: session,
            logging: workout,
            sync: SessionPendingWriteSyncAdapter(sync: sync, settings: settings),
            restTimer: restTimer,
            standardRestDuration: { settings.standardRestDuration.timeInterval },
            supersetRestDuration: { settings.supersetRestDuration.timeInterval },
            liveActivity: liveActivityAdapter,
            isCurrentSessionScope: { [workout] session in
                session.persistentModelID == workout.currentSession?.persistentModelID
            }
        )
        reconcileLiveActivity()
    }

    private func reconcileLiveActivity() {
        liveActivityAdapter.endIfInvalidated(
            displayedSession: workout.displayedSession,
            currentSession: workout.currentSession
        )
    }

    private func showSourceSession(for exercise: Exercise) {
        coordinator.cancelPairing()
        guard let session = exercise.session, let week = session.week else { return }
        workout.show(week: week.number, day: session.dayNumber)
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

}

extension SessionView {
    private func productionStage(for session: Session) -> some View {
        SessionStageView(
            session: session,
            coordinator: coordinator,
            actions: stageActions(in: session),
            onTopContentOffsetChange: updateSessionSettingsOverpull(topContentOffset:)
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            sessionHeaderHUD(session: session)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Gate on the published interval, not the time-derived `isRunning`: the interval is
            // held a beat past the deadline so the pill stays mounted to play the expiry buzz.
            if restTimer.interval != nil {
                RestPillView(restTimer: restTimer)
            }
        }
    }

    private func stageActions(in session: Session) -> SessionStageActions {
        SessionStageActions(
            focus: focusWithMorph,
            log: logWithMomentum,
            updateLoggedSet: coordinator.updateLoggedSet(_:as:),
            skip: skipWithFade,
            delete: coordinator.deleteLog(for:),
            focusSupersetExercise: { exercise in
                focusSupersetWithMorph(exercise, in: session)
            },
            dismissSuperset: { config in
                dismissSuperset(config, in: session)
            },
            showSourceSession: showSourceSession(for:),
            moveOn: {
                coordinator.cancelRestForSessionExit()
                workout.requestMoveOnCelebration()
            }
        )
    }

    private func updateSessionSettingsOverpull(topContentOffset: CGFloat) {
        sessionSettingsTopContentOffset = topContentOffset
        guard canRevealSessionControls else {
            if sessionSettingsOverpullState != .hidden {
                sessionSettingsOverpullState = .hidden
            }
            return
        }

        guard sessionSettingsDragStartTopContentOffset == nil else { return }

        applySessionSettingsOverpullState(
            sessionSettingsOverpullState.tracking(topContentOffset: topContentOffset)
        )
    }

    private func updateSessionSettingsOverpullDrag(translationHeight: CGFloat) {
        guard canRevealSessionControls, translationHeight > 0 else { return }
        let startTopContentOffset = sessionSettingsDragStartTopContentOffset ?? max(0, sessionSettingsTopContentOffset)
        sessionSettingsDragStartTopContentOffset = startTopContentOffset
        applySessionSettingsOverpullState(
            sessionSettingsOverpullState.tracking(
                topContentOffset: SessionSettingsOverpullState.overpullDistance(
                    startTopContentOffset: startTopContentOffset,
                    translationHeight: translationHeight * SessionSettingsHeaderDrag.overpullDamping
                )
            )
        )
    }

    private func finishSessionSettingsOverpullDrag() {
        let shouldStartIdleDismissal = sessionSettingsOverpullState.isPinned
        sessionSettingsDragStartTopContentOffset = nil
        if shouldStartIdleDismissal {
            startSessionSettingsOverpullIdleDismissal()
        }
    }

    private func applySessionSettingsOverpullState(_ state: SessionSettingsOverpullState) {
        guard state != sessionSettingsOverpullState else { return }
        let startsPinned = state.isPinned && !sessionSettingsOverpullState.isPinned
        sessionSettingsOverpullState = state
        if startsPinned, sessionSettingsDragStartTopContentOffset == nil {
            startSessionSettingsOverpullIdleDismissal()
        }
    }

    private func startSessionSettingsOverpullIdleDismissal() {
        sessionSettingsOverpullDismissalID += 1
    }

    /// The W1D1 · N-left · progress-rail header, floated as an inset Liquid Glass
    /// HUD pinned to the top. Content scrolls beneath it; over-pulling past the
    /// reveal threshold morphs it open to expose Settings on top.
    @ViewBuilder
    private func sessionHeaderHUD(session: Session) -> some View {
        SessionProgressHeader(
            session: session,
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
        .padding(.top, 1)
        .padding(.bottom, 2)
        .padding(.horizontal)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(sessionSettingsOverpullGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-header-hud")
    }

    private var sessionSettingsOverpullGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                updateSessionSettingsOverpullDrag(translationHeight: value.translation.height)
            }
            .onEnded { value in
                updateSessionSettingsOverpullDrag(translationHeight: value.translation.height)
                finishSessionSettingsOverpullDrag()
            }
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

}

private enum SessionSettingsHeaderDrag {
    static let overpullDamping: CGFloat = 0.4
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
                .font(Theme.font(.logCapsule))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Returns to the current session")
        .accessibilityIdentifier("go-back-current-session-button")
    }

    private var makeCurrentButton: some View {
        Button(action: onMakeCurrent) {
            Label("Make Current", systemImage: "pin.fill")
                .labelStyle(.iconOnly)
                .font(Theme.font(.logCapsule))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Makes the viewed session the current session")
        .accessibilityIdentifier("make-current-session-button")
    }
}


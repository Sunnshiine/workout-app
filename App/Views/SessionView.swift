import SwiftUI
import UIKit

struct SessionView: View {
    let liveActivityAdapter: LiveActivityProductionAdapter
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
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
    @State private var stageComposition = SessionStageComposition.reading

    init(liveActivityAdapter: LiveActivityProductionAdapter = LiveActivityProductionAdapter()) {
        self.liveActivityAdapter = liveActivityAdapter
    }

    var body: some View {
        Group {
            if let session = workout.viewedSession {
                VStack(spacing: 0) {
                    SyncStatusBanner(outcome: sync.outcome, isSyncing: sync.isSyncing)
                        .padding(.top, 8)

                    if !workout.isViewingLiveEdge {
                        OffLiveEdgeControls(
                            currentLabel: workout.currentSession?.address?.sessionLabel ?? "current",
                            onGoBack: {
                                sessionSettingsOverpullState = .hidden
                                workout.showCurrent()
                            },
                            onMakeCurrent: {
                                sessionSettingsOverpullState = .hidden
                                workout.makeViewedSessionCurrent()
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    productionStage(for: session)
                        .onAppear {
                            let isFirstBind = coordinator.session == nil
                            withTransaction(\.disablesAnimations, isFirstBind) {
                                bindCoordinator(to: session)
                            }
                        }
                        .onChange(of: session.persistentModelID) { _, _ in
                            bindCoordinator(to: session)
                        }
                }
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.25),
                    value: syncBannerText
                )
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
        .onChange(of: workout.viewedSession?.persistentModelID) { _, _ in
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

    private var syncBannerText: String? {
        SyncStatusBannerPresentation(outcome: sync.outcome, isSyncing: sync.isSyncing)?.text
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
            navigation: workout,
            motion: SwiftUISessionMotion()
        )
        reconcileLiveActivity()
    }

    private func reconcileLiveActivity() {
        liveActivityAdapter.endIfInvalidated(at: workout.liveEdge)
    }
}

extension SessionView {
    private func productionStage(for session: Session) -> some View {
        SessionStageView(
            session: session,
            coordinator: coordinator,
            composition: stageComposition,
            restTimer: restTimer
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if stageComposition == .reading {
                sessionHeaderHUD(session: session)
            }
        }
        .onPreferenceChange(EditingWeightPreferenceKey.self) { isEditingWeight in
            withAnimation(reduceMotion ? nil : Theme.stageCompositionAnimation) {
                stageComposition = SessionStageComposition(isEditingWeight: isEditingWeight)
            }
        }
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
        workout.viewedSession != nil && workout.isViewingLiveEdge && workout.moveOnCelebrationSession == nil
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
}

private struct SwiftUISessionMotion: SessionMotionPerforming {
    var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        guard let animation = motion.animation else {
            return try withTransaction(\.disablesAnimations, true, change)
        }
        try withAnimation(animation, change)
    }
}

private enum SessionSettingsHeaderDrag {
    static let overpullDamping: CGFloat = 0.4
}

private struct OffLiveEdgeControls: View {
    let currentLabel: String
    let onGoBack: () -> Void
    let onMakeCurrent: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack {
            goBackButton
            Spacer(minLength: 8)
            makeCurrentButton
        }
        .accessibilityElement(children: .contain)
    }

    private var goBackButton: some View {
        capsule("Back to \(currentLabel)", action: onGoBack)
            .accessibilityHint("Returns to the current session")
            .accessibilityIdentifier("go-back-current-session-button")
    }

    private var makeCurrentButton: some View {
        capsule("Make current", action: onMakeCurrent)
            .accessibilityHint("Makes the viewed session the current session")
            .accessibilityIdentifier("make-current-session-button")
    }

    private func capsule(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(.queuePill))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(palette.footFill, in: .capsule)
                .overlay(Capsule().strokeBorder(palette.queueStroke, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

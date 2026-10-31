import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette
    @Environment(AppEntryInbox.self) private var entry
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: SessionCoordinator
    @State private var isSettingsPresented = false
    @State private var stageComposition = SessionStageComposition.reading

    /// No Dictation leaves the mic off every card. `focus` is the process's active Set, which a
    /// headless Dictation reads too.
    init(wiring: SessionWiring, dictation: SetDictation? = nil, focus: ActiveSetFocusManager? = nil) {
        _coordinator = State(initialValue: SessionCoordinator(wiring: wiring, dictation: dictation, focus: focus))
    }

    var body: some View {
        Group {
            if let session = workout.viewedSession {
                VStack(spacing: 0) {
                    if !workout.isViewingLiveEdge {
                        OffLiveEdgeControls(
                            onGoBack: workout.showCurrent,
                            onMakeCurrent: workout.makeViewedSessionCurrent
                        )
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.top, 8)
                    }

                    productionStage(for: session)
                        .onAppear {
                            let isFirstBind = coordinator.sessionCoordinate == nil
                            withTransaction(\.disablesAnimations, isFirstBind) {
                                coordinator.view(session)
                            }
                        }
                        .onChange(of: session.persistentModelID) { _, _ in
                            coordinator.view(session)
                        }
                }
            } else {
                ScrollView {
                    EmptyStateView {
                        isSettingsPresented = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, 80)
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
        .onChange(of: entry.arrivals) {
            coordinator.answerEntry()
        }
        // The hold is for the athlete to glance at the written Set and undo it. Off screen there
        // is no glance, and a hold its Clear menu suspended would otherwise outlast the lock. An
        // Effort Countdown ends too, since its voice and timer cannot be trusted in the background.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            coordinator.endSpokenWriteHold()
            coordinator.cancelCountdown()
        }
        .onDisappear(perform: coordinator.cancelCountdown)
    }
}

extension SessionView {
    private func productionStage(for session: Session) -> some View {
        SessionStageView(
            session: session,
            coordinator: coordinator,
            composition: stageComposition,
            restTimer: coordinator.restTimer
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if stageComposition == .reading {
                // Fades as one image, so the HUD text never shows through the banner over it.
                sessionHeaderHUD(session: session)
                    .compositingGroup()
            }
        }
        .ignoresSafeArea(stageComposition == .reading ? .keyboard : [], edges: .bottom)
        .onPreferenceChange(EditingWeightPreferenceKey.self) { isEditingWeight in
            withAnimation(reduceMotion ? nil : Theme.stageCompositionAnimation) {
                stageComposition = SessionStageComposition(isEditingWeight: isEditingWeight)
            }
        }
    }

    private func sessionHeaderHUD(session: Session) -> some View {
        SessionProgressHeader(
            session: session,
            block: workout.block,
            currentSession: workout.currentSession,
            onNavigate: coordinator.cancelPairing
        )
        .padding(.top, 1)
        .padding(.bottom, 2)
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-header-hud")
        .overlay(alignment: .top) {
            SessionSyncBanner()
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
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

private struct SessionSyncBanner: View {
    @Environment(SyncCoordinator.self) private var sync

    var body: some View {
        SyncStatusBanner(outcome: sync.outcome, isSyncing: sync.isSyncing)
    }
}

private struct OffLiveEdgeControls: View {
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
            Label("Go back", systemImage: "arrow.backward")
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
            Label("Make current", systemImage: "play.fill")
                .labelStyle(.iconOnly)
                .font(Theme.font(.logCapsule))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Makes the viewed session the current session")
        .accessibilityIdentifier("make-current-session-button")
    }
}

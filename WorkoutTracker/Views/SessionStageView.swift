import SwiftUI
import UIKit

/// The production Session surface mutation handlers, animation-wrapped by
/// SessionView so every path keeps the coordinator's focus semantics.
struct SessionStageActions {
    let focus: (ExerciseSet) -> Void
    let log: (ExerciseSet, SetLog) -> Void
    let updateLoggedSet: (ExerciseSet, SetLog) -> Void
    let skip: (ExerciseSet) -> Void
    let delete: (ExerciseSet) -> Void
    let focusSupersetExercise: (Exercise) -> Void
    let dismissSuperset: (SessionSupersetRenderConfig) -> Void
    let showSourceSession: (Exercise) -> Void
    let moveOn: () -> Void
}

/// Stage: the Session screen is a single "now playing" surface — the Exercise
/// name, its context, and the active Set card. Orientation is on demand: an
/// up-next hint at the bottom and the full queue in a sheet.
struct SessionStageView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let actions: SessionStageActions
    let onTopContentOffsetChange: (CGFloat) -> Void
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isQueuePresented = false

    /// Open Exercises are makeup work from earlier Sessions, only meaningful
    /// while the athlete is at the live edge of their plan.
    private var liveEdgeOpenExercises: [Exercise] {
        workout.isViewingLiveEdge ? workout.openExercises : []
    }

    var body: some View {
        let items = SessionStagePresentation.items(
            coordinator.renderItems(in: session, lastPerformedLookup: lastPerformedLookup.snapshot)
        )
        let focusID = coordinator.visualFocusOwner?.setID ?? coordinator.activeSetID
        let stageItem = SessionStagePresentation.stageItem(in: items, focusID: focusID)

        VStack(spacing: 0) {
            ScrollView {
                WorkoutGlassContainer(spacing: Theme.cardSpacing) {
                    VStack(spacing: Theme.sectionSpacing) {
                        if let stageItem {
                            stageContent(stageItem, items: items)
                        } else {
                            completionStage(items: items)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Theme.sectionSpacing)
                    .padding(.bottom, Theme.cardSpacing)
                }
            }
            .scrollBounceBehavior(.always)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self, of: topContentOffset) { _, offset in
                onTopContentOffsetChange(offset)
            }

            queueBar(stageItem: stageItem, items: items)
        }
        .animation(
            reduceMotion ? nil : Theme.momentumFlowAnimation,
            value: SessionStagePresentation.stageIdentity(in: items, focusID: focusID)
        )
        .sheet(isPresented: $isQueuePresented) {
            SessionQueueSheet(
                items: items,
                stageItemID: stageItem?.id,
                showsMoveOn: workout.isViewingLiveEdge && workout.canMoveOn,
                openExercises: liveEdgeOpenExercises,
                pairingMode: coordinator.pairingMode,
                canBeginPairing: canBeginPairing(_:),
                onJump: jump(to:),
                onMoveOn: actions.moveOn,
                onSelectOpenExercise: actions.showSourceSession,
                onBeginPairing: beginPairing(from:),
                onPairingTap: handlePairingTap(on:),
                onCancelPairing: coordinator.cancelPairing
            )
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stageContent(_ item: SessionStageItem, items: [SessionStageItem]) -> some View {
        switch item.item {
        case .exercise(let config):
            exerciseStage(config, position: SessionStagePresentation.positionLabel(of: item, in: items))
        case .superset(let config):
            ActiveSupersetSection(
                config: config,
                onFocusExercise: actions.focusSupersetExercise,
                onLog: actions.log,
                onSkip: actions.skip,
                onDelete: actions.delete,
                onDismiss: { actions.dismissSuperset(config) }
            )
        case .hiddenPairedExercise:
            EmptyView()
        }
    }

    private func exerciseStage(_ config: SessionExerciseRenderConfig, position: String) -> some View {
        let sortedSets = config.exercise.sets.sorted { $0.index < $1.index }

        return VStack(spacing: 14) {
            Text(position)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(config.exercise.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            if let note = config.exercise.coachNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SessionStageSetDots(
                sets: sortedSets,
                currentSetID: config.activeSetID,
                dotSize: 9,
                onTap: actions.focus
            )
            .padding(.vertical, 2)

            if let lastPerformed = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformed)
            }

            stageCard(config, sortedSets: sortedSets)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stageCard(_ config: SessionExerciseRenderConfig, sortedSets: [ExerciseSet]) -> some View {
        if let expandedID = config.expandedLoggedSetID,
            let set = SessionStagePresentation.set(matching: expandedID, in: sortedSets) {
            LoggedSetReviewCard(
                set: set,
                setOrdinal: SessionStagePresentation.ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                showsSavedConfirmation: expandedID == config.savedLoggedSetID,
                onCommit: { actions.updateLoggedSet(set, $0) },
                onCollapse: { actions.focus(set) }
            )
            .id("stage-review-\(expandedID.exerciseOrder)-\(expandedID.setIndex)")
            .transition(.push(from: .bottom))
        } else if let set = SessionStagePresentation.stageSet(activeSetID: config.activeSetID, in: sortedSets) {
            ActiveSetCard(
                exercise: config.exercise,
                set: set,
                setOrdinal: SessionStagePresentation.ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                onLog: { actions.log(set, $0) },
                onSkip: { actions.skip(set) },
                onDelete: { actions.delete(set) }
            )
            .id("stage-active-\(config.exercise.order)-\(set.index)")
            .transition(.push(from: .bottom))
        }
    }

    private func completionStage(items: [SessionStageItem]) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(palette.accent)

            Text("Session complete")
                .font(.title2.weight(.bold))

            Text(SessionStagePresentation.completionSummary(for: items))
                .font(.callout)
                .foregroundStyle(.secondary)

            if !liveEdgeOpenExercises.isEmpty {
                OpenExercisesSection(
                    exercises: liveEdgeOpenExercises,
                    onSelect: actions.showSourceSession
                )
                .padding(.top, Theme.cardSpacing)
            }

            if workout.isViewingLiveEdge, workout.canMoveOn {
                SessionMoveOnButton(onTap: actions.moveOn)
                    .padding(.top, Theme.cardSpacing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.sectionSpacing)
    }

    // MARK: - Queue

    private func queueBar(stageItem: SessionStageItem?, items: [SessionStageItem]) -> some View {
        let upNext = SessionStagePresentation.upNextItem(after: stageItem, in: items)

        return HStack(spacing: 12) {
            if let upNext {
                Button {
                    jump(to: upNext)
                } label: {
                    HStack(spacing: 8) {
                        Text("Up next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .textCase(.uppercase)

                        Text(upNext.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .workoutGlass(.capsule)
                .accessibilityIdentifier("stage-up-next")
            }

            Spacer(minLength: 0)

            Button {
                isQueuePresented = true
            } label: {
                Label(
                    SessionStagePresentation.queueProgressLabel(for: items),
                    systemImage: "list.bullet"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.workoutGlass)
            .accessibilityIdentifier("stage-queue-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func jump(to item: SessionStageItem) {
        guard let nextSet = item.nextPendingSet else { return }
        actions.focus(nextSet)
    }

    // MARK: - Pairing

    private func canBeginPairing(_ item: SessionStageItem) -> Bool {
        guard item.exercises.count == 1, let exercise = item.exercises.first else { return false }
        return coordinator.canPair(exercise, in: session)
    }

    private func beginPairing(from item: SessionStageItem) {
        guard let exercise = item.exercises.first else { return }
        coordinator.beginPairing(from: exercise, in: session)
    }

    private func handlePairingTap(on item: SessionStageItem) {
        guard let exercise = item.exercises.first else { return }
        if coordinator.handlePairingTap(on: exercise, in: session) == .unavailable {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func topContentOffset(_ geometry: ScrollGeometry) -> CGFloat {
        -(geometry.contentOffset.y + geometry.contentInsets.top)
    }
}

/// The Move On affordance, shown on the completion stage and in the queue
/// sheet footer.
struct SessionMoveOnButton: View {
    var accessibilityID = "move-on-button"
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Move On", systemImage: "arrow.right")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.workoutGlass)
        .accessibilityHint("Advances to the next session")
        .accessibilityIdentifier(accessibilityID)
    }
}

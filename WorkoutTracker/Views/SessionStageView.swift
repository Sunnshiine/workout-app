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
    /// The Exercise whose history the sheet is showing — its only entry point is a tap on that
    /// Exercise's Last Performed line.
    @State private var historyExercise: Exercise?

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
        .sheet(item: $historyExercise) { exercise in
            ExerciseHistorySheet(
                presentation: ExerciseHistorySheetPresentation(
                    anchorBaseName: exercise.baseName,
                    entries: lastPerformedLookup.snapshot.history(baseName: exercise.baseName)
                ),
                fillProgress: lastPerformedLookup.fillProgress.map(HistoryFillProgressPresentation.init)
            )
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stageContent(_ item: SessionStageItem, items: [SessionStageItem]) -> some View {
        switch item.item {
        case .exercise(let config):
            exerciseStage(config)
        case .superset(let config):
            ActiveSupersetSection(
                config: config,
                onFocusExercise: actions.focusSupersetExercise,
                onShowHistory: { historyExercise = $0 },
                onLog: actions.log,
                onSkip: actions.skip,
                onDelete: actions.delete,
                onDismiss: { actions.dismissSuperset(config) }
            )
        case .hiddenPairedExercise:
            EmptyView()
        }
    }

    private func exerciseStage(_ config: SessionExerciseRenderConfig) -> some View {
        let sortedSets = config.exercise.sets.sorted { $0.index < $1.index }

        return VStack(spacing: 14) {
            if let cadence = config.exercise.cadence {
                Text(cadence)
                    .font(Theme.font(.cadence))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(config.exercise.name)
                .font(Theme.font(.exerciseName))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let note = config.exercise.coachNote {
                Text(note)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SessionStageBranch(
                sets: sortedSets,
                activeSetID: config.activeSetID,
                onTap: actions.focus
            )
            .padding(.vertical, 2)

            if let lastPerformed = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformed) {
                    historyExercise = config.exercise
                }
            }

            stageCard(config, sortedSets: sortedSets)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stageCard(_ config: SessionExerciseRenderConfig, sortedSets: [ExerciseSet]) -> some View {
        if let expandedID = config.expandedLoggedSetID,
            let set = SessionStagePresentation.set(matching: expandedID, in: sortedSets) {
            ActiveSetCard(
                exercise: config.exercise,
                set: set,
                setOrdinal: SessionStagePresentation.ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                mode: .reviewingLogged(
                    showsSavedConfirmation: expandedID == config.savedLoggedSetID,
                    onCollapse: { actions.focus(set) }
                ),
                onLog: { actions.updateLoggedSet(set, $0) },
                onSkip: { actions.skip(set) },
                onDelete: { actions.delete(set) }
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
                .font(Theme.glyphFont(size: 52))
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

        // The stage foot: an `N of M` queue pill owns position and opens the day's
        // Exercise queue sheet; beside it a plain `Up next ·` preview. The old
        // glass up-next bar is gone (DESIGN.md §5.1).
        return HStack(spacing: 12) {
            if let upNext {
                Button {
                    jump(to: upNext)
                } label: {
                    HStack(spacing: 5) {
                        Text("Up next ·")
                            .font(Theme.font(.queuePill))
                            .foregroundStyle(.secondary)

                        Text(upNext.title)
                            .font(Theme.font(.queuePill))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stage-up-next")
            }

            Spacer(minLength: 0)

            Button {
                isQueuePresented = true
            } label: {
                Text(SessionStagePresentation.queueProgressLabel(for: items))
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.footFill, in: .capsule)
                    .overlay(Capsule().strokeBorder(palette.queueStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
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

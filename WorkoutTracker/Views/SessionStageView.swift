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

        // Training surfaces never scroll (ledger §4.5, the Product Scale Rule): the
        // stage is a single page that fits, not a ScrollView, and the stage
        // container sheds its glass (glass dies in the contract slice).
        VStack(spacing: 0) {
            VStack(spacing: Theme.sectionSpacing) {
                if let stageItem {
                    stageContent(stageItem, items: items)
                } else {
                    completionStage(items: items)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal)
            .padding(.top, Theme.sectionSpacing)

            queueBar(stageItem: stageItem, items: items)
        }
        .animation(
            reduceMotion ? nil : Theme.momentumFlowAnimation,
            value: SessionStagePresentation.stageIdentity(in: items, focusID: focusID)
        )
        // The whole stage is the keyboard's escape surface: any tap that no control claims
        // resigns the weight field. Attached to the stage root so it covers the editorial
        // column, the card's chrome, and empty space alike — child buttons and gestures
        // keep priority over this parent tap, so controls behave unchanged.
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissKeyboard)
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

    // The left-aligned editorial column (pick session-stage-a, DESIGN.md §5.1):
    // the muted Cadence line (only when the Exercise carries a tempo), the
    // Fraunces Exercise name leading the page, the coach note, then the living
    // branch. The Active Set Card and its anchored Last Performed runline sink to
    // the foot, so the page reads top-to-bottom without scrolling.
    private func exerciseStage(_ config: SessionExerciseRenderConfig) -> some View {
        let sortedSets = config.exercise.sets.sorted { $0.index < $1.index }

        return VStack(alignment: .leading, spacing: 14) {
            if let cadence = config.exercise.cadence, !cadence.isEmpty {
                Text(cadence)
                    .font(Theme.font(.cadence))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("stage-cadence")
            }

            Text(config.exercise.baseName)
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stage-exercise-name")

            if let note = config.exercise.coachNote {
                Text(note)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SessionStageBranch(
                sets: sortedSets,
                activeSetID: config.activeSetID,
                onTap: actions.focus
            )
            .padding(.top, 4)

            Spacer(minLength: 12)

            if let lastPerformed = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformed) {
                    historyExercise = config.exercise
                }
            }

            stageCard(config, sortedSets: sortedSets)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // The completion stage sheds its extra icons (ledger §4.7): no checkmark, no
    // arrow — the branch is the page's one icon budget, and the reading is carried
    // in type-role text alone.
    private func completionStage(items: [SessionStageItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session complete")
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)

            Text(SessionStagePresentation.completionSummary(for: items))
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textSecondary)

            if !liveEdgeOpenExercises.isEmpty {
                OpenExercisesSection(
                    exercises: liveEdgeOpenExercises,
                    onSelect: actions.showSourceSession
                )
                .padding(.top, Theme.cardSpacing)
            }

            Spacer(minLength: 12)

            if workout.isViewingLiveEdge, workout.canMoveOn {
                SessionMoveOnButton(onTap: actions.moveOn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.sectionSpacing)
    }

    // MARK: - Queue

    // The stage foot (DESIGN.md §5.1, pick session-stage-a): a plain `Up next ·`
    // preview on the left and the `N of M` queue pill on the right. The old glass
    // up-next bar and its uppercase label + arrow icon are gone.
    private func queueBar(stageItem: SessionStageItem?, items: [SessionStageItem]) -> some View {
        let upNext = SessionStagePresentation.upNextItem(after: stageItem, in: items)

        return HStack(spacing: 12) {
            if let upNext {
                Button {
                    jump(to: upNext)
                } label: {
                    HStack(spacing: 5) {
                        Text("Up next ·")
                            .font(Theme.font(.queuePill))
                            .foregroundStyle(palette.textSecondary)

                        Text(upNext.title)
                            .font(Theme.font(.queuePill))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stage-up-next")
            }

            Spacer(minLength: 8)

            Button {
                isQueuePresented = true
            } label: {
                Text(SessionStagePresentation.queueProgressLabel(for: items))
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(palette.footFill, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(palette.queueStroke, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stage-queue-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func jump(to item: SessionStageItem) {
        guard let nextSet = item.nextPendingSet else { return }
        actions.focus(nextSet)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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
}

/// The Move On affordance, shown on the completion stage and in the queue
/// sheet footer.
struct SessionMoveOnButton: View {
    var accessibilityID = "move-on-button"
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

    // De-glassed (ledger §4): a plain green action capsule, text only — no arrow
    // icon (Green Means Action, One Icon Per Page).
    var body: some View {
        Button(action: onTap) {
            Text("Move On")
                .font(Theme.font(.logCapsule))
                .foregroundStyle(palette.actionText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(palette.action, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Advances to the next session")
        .accessibilityIdentifier(accessibilityID)
    }
}

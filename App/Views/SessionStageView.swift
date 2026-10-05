import SwiftUI
import UIKit

/// Stage: the Session screen is a single "now playing" surface — the Exercise
/// name, its context, and the active Set card. Orientation is on demand: an
/// up-next hint at the bottom and the full queue in a sheet.
struct SessionStageView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let composition: SessionStageComposition
    let restTimer: RestTimer
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(ExerciseHistoryFill.self) private var historyFill
    @Environment(\.themePalette) private var palette
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
            VStack(spacing: Theme.sectionSpacing) {
                if let stageItem {
                    stageContent(stageItem, items: items)
                } else {
                    completionStage(items: items)
                }
            }
            // The zero minimum keeps an overflowing column from growing this frame, which would
            // hand the overflow to a centering parent.
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal)
            .padding(.top, composition == .reading ? Theme.sectionSpacing : 0)

            ZStack {
                switch composition {
                case .reading:
                    queueBar(stageItem: stageItem, items: items)
                case .editingWeight:
                    Color.clear.frame(height: Theme.editingWeightFootGap)
                }
            }
            .overlay(alignment: .leading) { restPill }
        }
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
                onMoveOn: moveOn,
                onSelectOpenExercise: showSourceSession(of:),
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
                fillProgress: historyFill.progress.map(HistoryFillProgressPresentation.init)
            )
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stageContent(_ item: SessionStageItem, items: [SessionStageItem]) -> some View {
        switch item.item {
        case .exercise(let config):
            exerciseStage(config)
                .transition(.identity)
        case .superset(let config):
            ActiveSupersetSection(
                config: config,
                composition: composition,
                onFocusExercise: { coordinator.focusNextSupersetSet(for: $0, in: session) },
                onShowHistory: { historyExercise = $0 },
                onLog: { coordinator.log($0, as: $1) },
                onSkip: coordinator.skip(_:),
                onDelete: coordinator.deleteLog(for:)
            )
            .transition(.identity)
        case .hiddenPairedExercise:
            EmptyView()
        }
    }

    private func exerciseStage(_ config: SessionExerciseRenderConfig) -> some View {
        let sortedSets = config.exercise.sets.sorted { $0.index < $1.index }

        return SessionStageColumn(
            exercise: config.exercise,
            composition: composition,
            lastPerformed: config.lastPerformedPresentation.map { presentation in
                LastPerformedCard(presentation: presentation) {
                    historyExercise = config.exercise
                }
            }
        ) {
            Text(config.exercise.baseName)
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stage-exercise-name")
        } branch: {
            SessionStageBranch(
                sets: sortedSets,
                activeSetID: config.activeSetID,
                onTap: coordinator.focus(on:)
            )
        } card: {
            stageCard(config, sortedSets: sortedSets)
        }
    }

    /// One card call for review and logging alike, so a log, a focus change, or a review opening
    /// reuses the card instead of swapping it for another (DESIGN.md §5.2).
    @ViewBuilder
    private func stageCard(_ config: SessionExerciseRenderConfig, sortedSets: [ExerciseSet]) -> some View {
        let reviewedSet = config.expandedLoggedSetID.flatMap {
            SessionStagePresentation.set(matching: $0, in: sortedSets)
        }
        if let set = reviewedSet ?? SessionStagePresentation.stageSet(activeSetID: config.activeSetID, in: sortedSets) {
            let isReview = reviewedSet != nil
            ActiveSetCard(
                set: set,
                setOrdinal: SessionStagePresentation.ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                mode: isReview
                    ? .reviewingLogged(
                        showsSavedConfirmation: config.expandedLoggedSetID == config.savedLoggedSetID,
                        onCollapse: { coordinator.focus(on: set) }
                    )
                    : .logging,
                onLog: { isReview ? coordinator.updateLoggedSet(set, as: $0) : coordinator.log(set, as: $0) },
                onSkip: { coordinator.skip(set) },
                onDelete: { coordinator.deleteLog(for: set) }
            )
            .holdsStill(acrossChangesOf: "stage-\(isReview ? "review" : "active")-\(config.exercise.order)-\(set.index)")
        }
    }

    private func completionStage(items: [SessionStageItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session complete")
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)

            Text(SessionStagePresentation.completionSummary(for: items))
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textSecondary)

            openExercisesIfMoveOnStillFits

            if workout.isViewingLiveEdge, workout.canMoveOn {
                SessionMoveOnButton(onTap: moveOn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.sectionSpacing)
    }

    private var openExercisesIfMoveOnStillFits: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 14) {
                if !liveEdgeOpenExercises.isEmpty {
                    OpenExercisesSection(
                        exercises: liveEdgeOpenExercises,
                        onSelect: showSourceSession(of:)
                    )
                    .padding(.top, Theme.cardSpacing)
                }

                Spacer(minLength: 12)
            }
            Spacer(minLength: 12)
                .emptyFallbackNode()
        }
    }

    // MARK: - Queue

    // The stage foot (DESIGN.md §5.1, pick session-stage-a): a plain `Up next ·`
    // preview on the left and the `N of M` queue pill on the right. The old glass
    // up-next bar and its uppercase label + arrow icon are gone.
    private func queueBar(stageItem: SessionStageItem?, items: [SessionStageItem]) -> some View {
        let upNext = SessionStagePresentation.upNextItem(after: stageItem, in: items)
        let position = SessionStagePresentation.queuePosition(of: stageItem, in: items)

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
                .opacity(isResting ? 0 : 1)
                .accessibilityHidden(isResting)
                .allowsHitTesting(!isResting)
            }

            Spacer(minLength: 8)

            Button {
                isQueuePresented = true
            } label: {
                Text(position.label)
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
            .accessibilityLabel(position.accessibilityLabel)
            .accessibilityIdentifier("stage-queue-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Gated on the interval, not the time-derived `isRunning`: the interval is held a beat past
    /// the deadline so the pill stays mounted to play the expiry buzz.
    private var isResting: Bool {
        restTimer.interval != nil
    }

    /// Rest takes the `Up next` slot over a foot row that keeps its height, so the card never moves
    /// when rest starts or ends (DESIGN.md §5.1). One mount in both compositions keeps the pill's
    /// haptics running under a weight edit, where it shows nothing and takes no room.
    @ViewBuilder
    private var restPill: some View {
        if isResting {
            RestPillView(restTimer: restTimer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(composition == .reading ? 1 : 0)
                .accessibilityHidden(composition != .reading)
                .allowsHitTesting(composition == .reading)
        }
    }

    private func jump(to item: SessionStageItem) {
        guard let nextSet = item.nextPendingSet else { return }
        coordinator.focus(on: nextSet)
    }

    private func moveOn() {
        coordinator.cancelRestForSessionExit()
        workout.requestMoveOnCelebration()
    }

    private func showSourceSession(of exercise: Exercise) {
        coordinator.cancelPairing()
        guard let address = exercise.session?.address else { return }
        workout.show(address)
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

/// The card sits after the switch, at one position in both compositions, so its identity and the
/// weight field's focus survive the switch.
struct SessionStageColumn<Name: View, Branch: View, Card: View>: View {
    let exercise: Exercise
    let composition: SessionStageComposition
    let lastPerformed: LastPerformedCard?
    @ViewBuilder let name: () -> Name
    @ViewBuilder let branch: () -> Branch
    @ViewBuilder let card: () -> Card
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
            switch composition {
            case .reading:
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
                        cadenceLine
                        name()
                        noteLine
                        flexibleBranch
                        lastPerformed
                    }
                    VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
                        cadenceLine
                        name()
                        noteLine
                        flexibleBranch
                    }
                    VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
                        name()
                        noteLine
                        flexibleBranch
                    }
                    VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
                        name()
                        flexibleBranch
                    }
                    name()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            case .editingWeight:
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: Theme.stageColumnSpacing) {
                        name()
                        lastPerformed
                    }
                    lastPerformed
                    Color.clear.frame(height: 0)
                        .emptyFallbackNode()
                }
            }

            card()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flexibleBranch: some View {
        branch()
            .padding(.top, Theme.stageBranchTopPadding)
    }

    @ViewBuilder
    private var cadenceLine: some View {
        if let cadence = exercise.cadence, !cadence.isEmpty {
            Text(cadence)
                .font(Theme.font(.cadence))
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("stage-cadence")
        }
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note = exercise.coachNote {
            Text(note)
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// The verbs animate the branch's leaf and stem, never the card's frame or values. The `value:`
    /// form scopes the opt-out to the card's Set changing, so the rail recentring and the
    /// hold-to-skip fill that a finger starts inside the card still animate.
    func holdsStill(acrossChangesOf cardIdentity: String) -> some View {
        transaction(value: cardIdentity) { $0.animation = nil }
    }

    /// Falling back to a `ViewThatFits` candidate with no accessibility node leaves the last drawn
    /// candidate's elements in the tree, so a fallback that draws nothing carries an empty one.
    fileprivate func emptyFallbackNode() -> some View {
        accessibilityElement(children: .contain)
    }
}

/// The Move On affordance, shown on the completion stage and in the queue
/// sheet footer.
struct SessionMoveOnButton: View {
    var accessibilityID = "move-on-button"
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

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

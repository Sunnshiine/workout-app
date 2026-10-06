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
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(ExerciseHistoryFill.self) private var historyFill
    @Environment(\.themePalette) private var palette
    @State private var isQueuePresented = false
    /// The Exercise whose history the sheet is showing — its only entry point is a tap on that
    /// Exercise's Last Performed line.
    @State private var historyExercise: Exercise?

    var body: some View {
        let stage = coordinator.stage(in: session, lookup: lastPerformedLookup.snapshot)

        VStack(spacing: 0) {
            VStack(spacing: Theme.sectionSpacing) {
                switch stage.focus {
                case .exercise(let exercise):
                    exerciseStage(exercise)
                        .transition(.identity)
                case .superset(let superset):
                    ActiveSupersetSection(
                        stage: superset,
                        session: session,
                        coordinator: coordinator,
                        composition: composition,
                        onShowHistory: { historyExercise = $0 }
                    )
                    .transition(.identity)
                case .complete(let completion):
                    completionStage(completion)
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
                    queueBar(stage)
                case .editingWeight:
                    Color.clear.frame(height: Theme.editingWeightFootGap)
                }
            }
            .overlay(alignment: composition == .reading ? .leading : .topLeading) { restPill }
        }
        // The whole stage is the keyboard's escape surface: any tap that no control claims
        // resigns the weight field. Attached to the stage root so it covers the editorial
        // column, the card's chrome, and empty space alike — child buttons and gestures
        // keep priority over this parent tap, so controls behave unchanged.
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissKeyboard)
        .sheet(isPresented: $isQueuePresented) {
            SessionQueueSheet(queue: stage.queue, session: session, coordinator: coordinator)
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

    private func exerciseStage(_ stage: ExerciseStage) -> some View {
        SessionStageColumn(
            exercise: stage.exercise,
            composition: composition,
            lastPerformed: stage.lastPerformed.map { presentation in
                LastPerformedCard(presentation: presentation) {
                    historyExercise = stage.exercise
                }
            }
        ) {
            Text(stage.exercise.baseName)
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stage-exercise-name")
        } branch: {
            SessionStageBranch(branch: stage.branch, onTap: coordinator.focus(on:))
        } card: {
            if let slot = stage.card {
                ActiveSetCard(slot: slot, coordinator: coordinator)
                    .holdsStill(acrossChangesOf: slot.id)
            }
        }
    }

    private func completionStage(_ completion: CompletionStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session complete")
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)

            Text(completion.summary)
                .font(Theme.font(.coachNote))
                .foregroundStyle(palette.textSecondary)

            openExercisesIfMoveOnStillFits(completion.openExercises)

            if completion.showsMoveOn {
                SessionMoveOnButton(onTap: coordinator.moveOn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.sectionSpacing)
    }

    private func openExercisesIfMoveOnStillFits(_ openExercises: [Exercise]) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 14) {
                if !openExercises.isEmpty {
                    OpenExercisesSection(
                        exercises: openExercises,
                        onSelect: coordinator.showSourceSession(of:)
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
    private func queueBar(_ stage: SessionStage) -> some View {
        HStack(spacing: 12) {
            if let upNext = stage.upNext {
                Button {
                    if let target = upNext.target {
                        coordinator.focus(on: target)
                    }
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
                .opacity(isRestPillMounted ? 0 : 1)
                .accessibilityHidden(isRestPillMounted)
                .allowsHitTesting(!isRestPillMounted)
            }

            Spacer(minLength: 8)

            Button {
                isQueuePresented = true
            } label: {
                Text(stage.queue.position.label)
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
            .accessibilityLabel(stage.queue.position.accessibilityLabel)
            .accessibilityIdentifier("stage-queue-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var isRestPillMounted: Bool {
        restTimer.interval != nil
    }

    @ViewBuilder
    private var restPill: some View {
        if isRestPillMounted {
            RestPillView(restTimer: restTimer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(composition == .reading ? 1 : 0)
                .accessibilityHidden(composition != .reading)
                .allowsHitTesting(composition == .reading)
                .animation(nil, value: composition)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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

extension ActiveSetCard {
    init(slot: SetCardSlot, coordinator: SessionCoordinator) {
        switch slot.mode {
        case .logging:
            self.init(
                set: slot.set,
                setOrdinal: slot.ordinal,
                setCount: slot.count,
                mode: .logging,
                onLog: { coordinator.log(slot.set, as: $0) },
                onSkip: { coordinator.skip(slot.set) },
                onDelete: { coordinator.deleteLog(for: slot.set) }
            )
        case .reviewingLogged(let showsSavedConfirmation):
            self.init(
                set: slot.set,
                setOrdinal: slot.ordinal,
                setCount: slot.count,
                mode: .reviewingLogged(
                    showsSavedConfirmation: showsSavedConfirmation,
                    onCollapse: { coordinator.focus(on: slot.set) }
                ),
                onLog: { coordinator.updateLoggedSet(slot.set, as: $0) },
                onSkip: { coordinator.skip(slot.set) },
                onDelete: { coordinator.deleteLog(for: slot.set) }
            )
        }
    }
}

extension View {
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

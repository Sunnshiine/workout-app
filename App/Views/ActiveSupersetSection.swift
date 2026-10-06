import SwiftUI

/// The Superset stage (DESIGN.md §5.4, picks superset-stage4-a/-b): the same
/// editorial column as a single Exercise — Cadence, the Fraunces name, the coach
/// note, the branch, Last Performed, and the Active Set Card — but the name gains
/// a subordinate "& partner" line and the branch becomes **one forked stem**. The
/// focused Exercise leads; the "& partner" line is the manual focus switch onto
/// the resting side. Superset mechanics (alternation, pairing, the queue sheet's
/// containment) are untouched — this slice rebuilds only the composition.
struct ActiveSupersetSection: View {
    let config: SessionSupersetRenderConfig
    let composition: SessionStageComposition
    let onFocusExercise: (Exercise) -> Void
    let onShowHistory: (Exercise) -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    @Environment(\.themePalette) private var palette

    private var orderedExercises: [Exercise] {
        config.exercises.sorted { $0.order < $1.order }
    }

    /// The Exercise the stage follows: the active side, else the container (the
    /// lower-ordered side) when neither is active.
    private var focusedExercise: Exercise {
        if let active = config.exercises.first(where: { $0.order == config.presentation.activeExerciseOrder }) {
            return active
        }
        return orderedExercises.first ?? config.exercises[0]
    }

    private var partnerExercise: Exercise {
        config.exercises.first { $0.order != focusedExercise.order } ?? focusedExercise
    }

    private var focusedSortedSets: [ExerciseSet] {
        focusedExercise.sets.sorted { $0.index < $1.index }
    }

    /// The Set on stage: the active Set when one is focused, else the focused
    /// side's next Pending Set — so the card follows the focus (DESIGN.md §5.4).
    private var stageSet: ExerciseSet? {
        if let activeSetID = config.presentation.activeSetID {
            return focusedSortedSets.first { $0.index == activeSetID.setIndex }
        }
        return SupersetState.nextPendingSet(for: focusedExercise)
    }

    var body: some View {
        SessionStageColumn(
            exercise: focusedExercise,
            composition: composition,
            lastPerformed: config.lastPerformedPresentation.map { presentation in
                LastPerformedCard(presentation: presentation) {
                    onShowHistory(focusedExercise)
                }
            }
        ) {
            nameBlock
        } branch: {
            SessionStageBranch(
                sets: focusedSortedSets,
                activeSetID: config.presentation.activeSetID,
                partnerSets: partnerExercise.sets.sorted { $0.index < $1.index }
            )
        } card: {
            cardRegion
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(focusedExercise.baseName)
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stage-exercise-name")

            Button {
                onFocusExercise(partnerExercise)
            } label: {
                Text("& \(partnerExercise.baseName)")
                    .font(Theme.font(.supersetPartner))
                    .foregroundStyle(palette.supersetPartnerName)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("& \(partnerExercise.baseName)")
            .accessibilityHint("Switches focus to \(partnerExercise.baseName)")
            .accessibilityIdentifier("superset-partner-name")
        }
    }

    @ViewBuilder
    private var cardRegion: some View {
        if let activeSetID = config.presentation.activeSetID, let activeSet = stageSet {
            IncomingActiveSetCard(
                transition: incomingTransition,
                set: activeSet,
                setOrdinal: setOrdinal(for: activeSet),
                setCount: focusedSortedSets.count,
                onLog: { onLog(activeSet, $0) },
                onSkip: { onSkip(activeSet) },
                onDelete: { onDelete(activeSet) }
            )
            .id(activeSetID)
        } else if let fallbackSet = stageSet {
            ActiveSetCard(
                set: fallbackSet,
                setOrdinal: setOrdinal(for: fallbackSet),
                setCount: focusedSortedSets.count,
                onLog: { onLog(fallbackSet, $0) },
                onSkip: { onSkip(fallbackSet) },
                onDelete: { onDelete(fallbackSet) }
            )
        }
    }

    private var incomingTransition: ActiveSetTransition? {
        guard config.activeSetTransition?.incomingSetID == config.presentation.activeSetID else { return nil }
        return config.activeSetTransition
    }

    private func setOrdinal(for set: ExerciseSet) -> Int {
        (focusedSortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }
}

private struct IncomingActiveSetCard: View {
    let transition: ActiveSetTransition?
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    @State private var hasSettled = false

    var body: some View {
        ActiveSetCard(
            set: set,
            setOrdinal: setOrdinal,
            setCount: setCount,
            onLog: onLog,
            onSkip: onSkip,
            onDelete: onDelete
        )
        .offset(y: shouldAnimate && !hasSettled ? incomingOffset : 0)
        .opacity(shouldAnimate && !hasSettled ? 0 : 1)
        .onAppear(perform: runIncomingAnimationIfNeeded)
        .onChange(of: transition) { _, _ in
            runIncomingAnimationIfNeeded()
        }
    }

    private var shouldAnimate: Bool {
        transition != nil
    }

    private var incomingOffset: CGFloat {
        guard let transition else { return 0 }
        switch transition.kind {
        case .momentumFlow:
            return Theme.momentumRiseOffset
        case .softFadeUp:
            return 0
        case .collapseAndRise:
            return Theme.exerciseRiseOffset
        }
    }

    private var animation: Animation {
        guard let transition else { return .default }
        switch transition.kind {
        case .momentumFlow:
            return Theme.momentumRiseAnimation
        case .softFadeUp:
            return Theme.skipFadeUpAnimation
        case .collapseAndRise:
            return Theme.exerciseRiseAnimation
        }
    }

    private func runIncomingAnimationIfNeeded() {
        guard shouldAnimate else {
            hasSettled = true
            return
        }
        hasSettled = false
        withAnimation(animation) {
            hasSettled = true
        }
    }
}

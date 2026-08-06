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
    let onFocusExercise: (Exercise) -> Void
    let onShowHistory: (Exercise) -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    /// Retired from the stage: Unlink now lives in the queue sheet's containment
    /// group (DESIGN.md §5.4). Kept so the call site's dismiss wiring is untouched.
    let onDismiss: () -> Void
    /// The stage's tap-anywhere keyboard escape, threaded through to the Active Set Card.
    var inputDismissalRequestID = 0
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
        VStack(alignment: .leading, spacing: 14) {
            if let cadence = focusedExercise.cadence, !cadence.isEmpty {
                Text(cadence)
                    .font(Theme.font(.cadence))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("stage-cadence")
            }

            nameBlock

            if let note = focusedExercise.coachNote {
                Text(note)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SessionStageBranch(
                sets: focusedSortedSets,
                activeSetID: config.presentation.activeSetID,
                partnerSets: partnerExercise.sets.sorted { $0.index < $1.index }
            )
            .padding(.top, 4)

            Spacer(minLength: 12)

            if let lastPerformed = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformed) {
                    onShowHistory(focusedExercise)
                }
            }

            cardRegion
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The focused Exercise's Fraunces name leads; below it the subordinate
    // "& partner" line (foliage green by Day, translucent foliage at Night) is the
    // manual focus switch onto the resting side (DESIGN.md §5.4).
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
                    .foregroundStyle(palette.supersetPartnerBranch)
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
            ZStack(alignment: .topLeading) {
                IncomingActiveSetCard(
                    transition: incomingTransition,
                    exercise: focusedExercise,
                    set: activeSet,
                    setOrdinal: setOrdinal(for: activeSet),
                    setCount: focusedSortedSets.count,
                    onLog: { onLog(activeSet, $0) },
                    onSkip: { onSkip(activeSet) },
                    onDelete: { onDelete(activeSet) },
                    inputDismissalRequestID: inputDismissalRequestID
                )

                if let transition = config.retiringTransition, transition.outgoingSetID == activeSetID {
                    RetiringActiveSetCard(
                        transition: transition,
                        exercise: focusedExercise,
                        set: activeSet,
                        setOrdinal: setOrdinal(for: activeSet),
                        setCount: focusedSortedSets.count
                    )
                }
            }
            .id(activeSetID)
        } else if let fallbackSet = stageSet {
            ActiveSetCard(
                exercise: focusedExercise,
                set: fallbackSet,
                setOrdinal: setOrdinal(for: fallbackSet),
                setCount: focusedSortedSets.count,
                onLog: { onLog(fallbackSet, $0) },
                onSkip: { onSkip(fallbackSet) },
                onDelete: { onDelete(fallbackSet) },
                externalInputDismissalRequestID: inputDismissalRequestID
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
    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    var inputDismissalRequestID = 0
    @State private var hasSettled = false

    var body: some View {
        ActiveSetCard(
            exercise: exercise,
            set: set,
            setOrdinal: setOrdinal,
            setCount: setCount,
            onLog: onLog,
            onSkip: onSkip,
            onDelete: onDelete,
            externalInputDismissalRequestID: inputDismissalRequestID
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

private struct RetiringActiveSetCard: View {
    let transition: ActiveSetTransition
    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    @State private var hasRetired = false

    var body: some View {
        ActiveSetCard(
            exercise: exercise,
            set: set,
            setOrdinal: setOrdinal,
            setCount: setCount,
            onLog: { _ in },
            onSkip: {},
            onDelete: {},
            showsLoggedCheckmark: transition.kind == .momentumFlow
        )
        .allowsHitTesting(false)
        .offset(y: retiringOffset)
        .scaleEffect(x: 1, y: retiringScale, anchor: .top)
        .opacity(hasRetired ? 0 : 1)
        .onAppear {
            withAnimation(retiringAnimation) {
                hasRetired = true
            }
        }
    }

    private var retiringOffset: CGFloat {
        guard hasRetired else { return 0 }
        switch transition.kind {
        case .momentumFlow:
            return Theme.momentumDropOffset
        case .softFadeUp:
            return Theme.skipFadeUpOffset
        case .collapseAndRise:
            return 0
        }
    }

    private var retiringScale: CGFloat {
        guard hasRetired else { return 1 }
        switch transition.kind {
        case .momentumFlow:
            return 1
        case .softFadeUp, .collapseAndRise:
            return Theme.exerciseCompressionScale
        }
    }

    private var retiringAnimation: Animation {
        switch transition.kind {
        case .momentumFlow:
            return Theme.momentumDropAnimation
        case .softFadeUp:
            return Theme.skipFadeUpAnimation
        case .collapseAndRise:
            return Theme.exerciseCollapseAnimation
        }
    }
}

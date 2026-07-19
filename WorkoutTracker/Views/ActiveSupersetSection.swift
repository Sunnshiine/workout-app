import SwiftUI

/// The Superset stage: a single forked stem with the focused Exercise's name in
/// the warm serif voice, the partner's "& partner" name line as the manual focus
/// switch, and the Coach Note / Last Performed / Active Set Card all following the
/// focus (DESIGN.md §5.4). The fork + focus derivation lives in
/// `SessionStagePresentation.supersetFork`; dissolution moved to the queue sheet.
struct ActiveSupersetSection: View {
    let config: SessionSupersetRenderConfig
    let onFocusExercise: (Exercise) -> Void
    let onShowHistory: (Exercise) -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    @Namespace private var focusMorphNamespace

    private var fork: SupersetForkPresentation? {
        SessionStagePresentation.supersetFork(
            exercises: config.exercises,
            focusID: config.presentation.activeSetID
        )
    }

    private func exercise(order: Int?) -> Exercise? {
        guard let order else { return nil }
        return config.exercises.first { $0.order == order }
    }

    private var focusedExercise: Exercise? { exercise(order: fork?.focusedBranch?.exerciseOrder) }
    private var partnerExercise: Exercise? { exercise(order: fork?.partnerBranch?.exerciseOrder) }

    private var activeExercise: Exercise? {
        config.exercises.first { $0.order == config.presentation.activeExerciseOrder }
    }

    private var activeSet: ExerciseSet? {
        guard let activeSetID = config.presentation.activeSetID else { return nil }
        return activeExercise?.sets.first { $0.index == activeSetID.setIndex }
    }

    private var sortedActiveSets: [ExerciseSet] {
        activeExercise?.sets.sorted { $0.index < $1.index } ?? []
    }

    /// Focus is switchable only once a Set on the pair is active; before that the
    /// Superset simply reads (matching the pre-Greenhouse resting composition).
    private var isInteractive: Bool { config.presentation.activeSetID != nil }

    var body: some View {
        VStack(spacing: 14) {
            nameBlock

            if let note = focusedExercise?.coachNote {
                Text(note)
                    .font(Theme.font(.coachNote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let fork {
                SupersetForkBranch(fork: fork)
                    .padding(.vertical, 2)
            }

            if let lastPerformed = config.lastPerformedPresentation, let focusedExercise {
                // Tapping opens the Exercise History sheet for the focused side — the PRD gives the
                // Last Performed tap no Superset carve-out, so the seam bubbles up to SessionStageView.
                LastPerformedCard(presentation: lastPerformed) {
                    onShowHistory(focusedExercise)
                }
            }

            if let activeSetID = config.presentation.activeSetID, let activeExercise, let activeSet {
                activeCard(activeSetID: activeSetID, activeExercise: activeExercise, activeSet: activeSet)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var nameBlock: some View {
        VStack(spacing: 6) {
            if let cadence = focusedExercise?.cadence {
                Text(cadence)
                    .font(Theme.font(.cadence))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(focusedExercise?.name ?? "")
                .font(Theme.font(.exerciseName))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let partner = partnerExercise {
                partnerNameLine(partner)
            }
        }
    }

    @ViewBuilder
    private func partnerNameLine(_ partner: Exercise) -> some View {
        let label = Text("& \(partner.name)")
            .font(Theme.font(.supersetPartner))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)

        if isInteractive {
            // The "& partner" name line is the manual focus switch (DESIGN.md §5.4).
            Button {
                onFocusExercise(partner)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Switches focus to this exercise")
            .accessibilityIdentifier("superset-partner-name")
        } else {
            label.accessibilityIdentifier("superset-partner-name")
        }
    }

    @ViewBuilder
    private func activeCard(
        activeSetID: ActiveSetID,
        activeExercise: Exercise,
        activeSet: ExerciseSet
    ) -> some View {
        ZStack(alignment: .topLeading) {
            focusMorphSurface(
                for: activeSetID,
                content: IncomingActiveSetCard(
                    transition: incomingTransition,
                    exercise: activeExercise,
                    set: activeSet,
                    setOrdinal: setOrdinal(for: activeSet),
                    setCount: sortedActiveSets.count,
                    onLog: { onLog(activeSet, $0) },
                    onSkip: { onSkip(activeSet) },
                    onDelete: { onDelete(activeSet) }
                )
            )

            if let transition = config.retiringTransition, transition.outgoingSetID == activeSetID {
                RetiringActiveSetCard(
                    transition: transition,
                    exercise: activeExercise,
                    set: activeSet,
                    setOrdinal: setOrdinal(for: activeSet),
                    setCount: sortedActiveSets.count
                )
            }
        }
        .id(activeSetID)
    }

    private var incomingTransition: ActiveSetTransition? {
        guard config.activeSetTransition?.incomingSetID == config.presentation.activeSetID else { return nil }
        return config.activeSetTransition
    }

    private func setOrdinal(for set: ExerciseSet) -> Int {
        (sortedActiveSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }

    private var shouldUseFocusMorph: Bool {
        config.activeSetTransition == nil && config.retiringTransition == nil
    }

    @ViewBuilder
    private func focusMorphSurface<Content: View>(for setID: ActiveSetID?, content: Content) -> some View {
        if let setID, shouldUseFocusMorph {
            content.matchedGeometryEffect(
                id: "superset-focus-morph-\(setID.exerciseOrder)-\(setID.setIndex)",
                in: focusMorphNamespace
            )
        } else {
            content
        }
    }
}

private struct IncomingActiveSetCard: View {
    let transition: ActiveSetTransition?
    let exercise: Exercise
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var identityLabel: String?
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
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
            identityLabel: identityLabel
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
    var identityLabel: String?
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
            showsLoggedCheckmark: transition.kind == .momentumFlow,
            identityLabel: identityLabel
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

import SwiftUI

struct ExerciseSection: View {
    let exercise: Exercise
    let lastPerformedIndex: LastPerformedIndex
    let activeSetID: ActiveSetID?
    let activeSetTransition: ActiveSetTransition?
    let retiringTransition: ActiveSetTransition?
    let isCollapsed: Bool
    let onFocus: (ExerciseSet) -> Void
    let onReexpand: () -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    @State private var hasCompletedRise = true

    private var sortedSets: [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    private var lastPerformedPresentation: LastPerformedCardPresentation? {
        LastPerformedCardPresentation(exercise: exercise, index: lastPerformedIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCollapsed {
                ExerciseSummaryRow(exercise: exercise, onTap: onReexpand)
                    .transition(
                        .scale(scale: Theme.exerciseCompressionScale, anchor: .top)
                            .combined(with: .opacity)
                    )
            } else {
                Text(exercise.name)
                    .font(.headline)

                if let note = exercise.coachNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let lastPerformedPresentation {
                    LastPerformedCard(presentation: lastPerformedPresentation)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedSets, id: \.persistentModelID) { set in
                        let setID = ActiveSetFocusManager.id(for: set)
                        let scrollID = setID ?? ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index)
                        ZStack(alignment: .topLeading) {
                            if setID == activeSetID {
                                IncomingActiveSetCard(
                                    transition: incomingTransition(for: setID),
                                    exercise: exercise,
                                    set: set,
                                    setOrdinal: setOrdinal(for: set),
                                    setCount: sortedSets.count,
                                    onLog: { onLog(set, $0) },
                                    onSkip: { onSkip(set) },
                                    onDelete: { onDelete(set) }
                                )
                            } else {
                                SetRow(set: set) {
                                    onFocus(set)
                                }
                            }

                            if let transition = retiringTransition, transition.outgoingSetID == setID {
                                RetiringActiveSetCard(
                                    transition: transition,
                                    exercise: exercise,
                                    set: set,
                                    setOrdinal: setOrdinal(for: set),
                                    setCount: sortedSets.count
                                )
                            }
                        }
                        .id(scrollID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .offset(y: shouldRiseAfterCompletion && !hasCompletedRise ? Theme.exerciseRiseOffset : 0)
        .opacity(shouldRiseAfterCompletion && !hasCompletedRise ? 0.35 : 1)
        .animation(Theme.exerciseCollapseAnimation, value: isCollapsed)
        .onAppear(perform: runCompletionRiseIfNeeded)
        .onChange(of: activeSetTransition) { _, _ in
            runCompletionRiseIfNeeded()
        }
    }

    private var shouldRiseAfterCompletion: Bool {
        activeSetTransition?.kind == .collapseAndRise
            && activeSetTransition?.incomingSetID?.exerciseOrder == exercise.order
    }

    private func incomingTransition(for setID: ActiveSetID?) -> ActiveSetTransition? {
        guard let setID, activeSetTransition?.incomingSetID == setID else { return nil }
        return activeSetTransition
    }

    private func runCompletionRiseIfNeeded() {
        guard shouldRiseAfterCompletion else {
            hasCompletedRise = true
            return
        }
        hasCompletedRise = false
        withAnimation(Theme.exerciseRiseAnimation) {
            hasCompletedRise = true
        }
    }

    private func setOrdinal(for set: ExerciseSet) -> Int {
        (sortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
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
    @State private var hasSettled = false

    var body: some View {
        ActiveSetCard(
            exercise: exercise,
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

import SwiftUI

struct ExerciseSection: View {
    let config: SessionExerciseRenderConfig
    let onFocus: (ExerciseSet) -> Void
    let onReexpand: () -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onUpdateLoggedSet: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    var onBeginPairing: () -> Void = {}
    var onPairingTap: () -> Void = {}
    @State private var hasCompletedRise = true
    @Environment(\.themePalette) private var palette
    @Namespace private var focusMorphNamespace

    private var exercise: Exercise {
        config.exercise
    }

    private var sortedSets: [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if config.isCollapsed {
                ExerciseSummaryRow(exercise: exercise, onTap: onReexpand)
                    .transition(
                        .scale(scale: Theme.exerciseCompressionScale, anchor: .top)
                            .combined(with: .opacity)
                    )
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(exercise.name)
                        .font(.title3.weight(.bold))

                    Spacer(minLength: 0)

                    if config.showsPairingGrip {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                if let note = exercise.coachNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let lastPerformedPresentation = config.lastPerformedPresentation {
                    LastPerformedCard(presentation: lastPerformedPresentation)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedSets, id: \.persistentModelID) { set in
                        let setID = SessionCoordinator.activeSetID(for: set)
                        let scrollID = setID ?? ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index)
                        ZStack(alignment: .topLeading) {
                            if setID == config.expandedLoggedSetID {
                                focusMorphSurface(
                                    for: set,
                                    content: LoggedSetReviewCard(
                                        set: set,
                                        setOrdinal: setOrdinal(for: set),
                                        setCount: sortedSets.count,
                                        showsSavedConfirmation: setID == config.savedLoggedSetID,
                                        onCommit: { onUpdateLoggedSet(set, $0) },
                                        onCollapse: { onFocus(set) }
                                    )
                                )
                            } else if setID == config.activeSetID {
                                focusMorphSurface(
                                    for: set,
                                    content: IncomingActiveSetCard(
                                        transition: incomingTransition(for: setID),
                                        exercise: exercise,
                                        set: set,
                                        setOrdinal: setOrdinal(for: set),
                                        setCount: sortedSets.count,
                                        onLog: { onLog(set, $0) },
                                        onSkip: { onSkip(set) },
                                        onDelete: { onDelete(set) }
                                    )
                                )
                            } else {
                                focusMorphSurface(
                                    for: set,
                                    content: SetRow(
                                        set: set,
                                        showsSavedConfirmation: setID == config.savedLoggedSetID
                                    ) {
                                        onFocus(set)
                                    }
                                )
                            }

                            if let transition = config.retiringTransition, transition.outgoingSetID == setID {
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
        .overlay {
            if config.isPairingConfirmation {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(palette.accent, lineWidth: 2)
                    .shadow(color: palette.accent.opacity(0.65), radius: 12)
                    .padding(-Theme.pairingConfirmationRingBleed)
            }
        }
        .overlay {
            if config.pairingAvailability != .inactive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onPairingTap)
            }
        }
        .opacity(config.pairingAvailability == .unavailable ? Theme.pairingUnavailableOpacity : 1)
        .offset(y: shouldRiseAfterCompletion && !hasCompletedRise ? Theme.exerciseRiseOffset : 0)
        .opacity(shouldRiseAfterCompletion && !hasCompletedRise ? 0.35 : 1)
        .animation(Theme.exerciseCollapseAnimation, value: config.isCollapsed)
        .animation(.easeInOut(duration: 0.18), value: config.pairingAvailability == .unavailable)
        .onLongPressGesture(perform: onBeginPairing)
        .onAppear(perform: runCompletionRiseIfNeeded)
        .onChange(of: config.activeSetTransition) { _, _ in
            runCompletionRiseIfNeeded()
        }
    }

    private var shouldRiseAfterCompletion: Bool {
        config.activeSetTransition?.kind == .collapseAndRise
            && config.activeSetTransition?.incomingSetID?.exerciseOrder == exercise.order
    }

    private func incomingTransition(for setID: ActiveSetID?) -> ActiveSetTransition? {
        guard let setID, config.activeSetTransition?.incomingSetID == setID else { return nil }
        return config.activeSetTransition
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

    private var shouldUseFocusMorph: Bool {
        config.activeSetTransition == nil && config.retiringTransition == nil
    }

    @ViewBuilder
    private func focusMorphSurface<Content: View>(for set: ExerciseSet, content: Content) -> some View {
        if shouldUseFocusMorph {
            content.matchedGeometryEffect(
                id: "focus-morph-\(exercise.order)-\(set.index)",
                in: focusMorphNamespace
            )
        } else {
            content
        }
    }
}

struct ActiveSupersetSection: View {
    let config: SessionSupersetRenderConfig
    let onFocusExercise: (Exercise) -> Void
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void
    let onDismiss: () -> Void
    @Environment(\.themePalette) private var palette
    @Namespace private var focusMorphNamespace

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let activeSetID = config.presentation.activeSetID, let activeExercise, let activeSet {
                activeRegion(activeSetID: activeSetID, activeExercise: activeExercise, activeSet: activeSet)
                    .padding(.top, Theme.cardSpacing)

                if let restingSide = config.presentation.sides.first(where: { !$0.isActive }) {
                    restingStrip(for: restingSide)
                        .padding(.top, Theme.supersetRestingSpacing)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(config.presentation.sides, id: \.exerciseOrder) { side in
                        restingStrip(for: side)
                    }
                }
                .padding(.top, Theme.cardSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Superset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)

            pairIndicator

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "link.badge.minus")
                    .font(.callout.weight(.semibold))
                    .accessibilityLabel("Dismiss superset")
            }
            .buttonStyle(.workoutGlass)
        }
    }

    private var pairIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(config.presentation.sides.enumerated()), id: \.element.exerciseOrder) { index, side in
                if index > 0 {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                SupersetIdentityBadge(label: identityLabel(forSideIndex: index), isActive: side.isActive)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func activeRegion(
        activeSetID: ActiveSetID,
        activeExercise: Exercise,
        activeSet: ExerciseSet
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastPerformedPresentation = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformedPresentation)
            }

            ZStack(alignment: .topLeading) {
                focusMorphSurface(
                    for: activeSetID,
                    content: IncomingActiveSetCard(
                        transition: incomingTransition,
                        exercise: activeExercise,
                        set: activeSet,
                        setOrdinal: setOrdinal(for: activeSet),
                        setCount: sortedActiveSets.count,
                        identityLabel: identityLabel(forExerciseOrder: activeSetID.exerciseOrder),
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
                        setCount: sortedActiveSets.count,
                        identityLabel: identityLabel(forExerciseOrder: activeSetID.exerciseOrder)
                    )
                }
            }
            .id(activeSetID)
        }
    }

    @ViewBuilder
    private func restingStrip(for side: ActiveSupersetSidePresentation) -> some View {
        let isInteractive = config.presentation.activeSetID != nil
        let strip = SupersetRestingStrip(
            side: side,
            identityLabel: identityLabel(forExerciseOrder: side.exerciseOrder),
            isInteractive: isInteractive
        )

        if isInteractive {
            Button {
                guard let exercise = config.exercises.first(where: { $0.order == side.exerciseOrder }) else {
                    return
                }
                onFocusExercise(exercise)
            } label: {
                focusMorphSurface(for: nextPendingSetID(for: side.exerciseOrder), content: strip)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Switches to this exercise's next pending set")
        } else {
            focusMorphSurface(for: nextPendingSetID(for: side.exerciseOrder), content: strip)
        }
    }

    private func identityLabel(forSideIndex index: Int) -> String {
        index == 0 ? "A" : "B"
    }

    private func identityLabel(forExerciseOrder order: Int) -> String {
        guard let index = config.presentation.sides.firstIndex(where: { $0.exerciseOrder == order }) else {
            return ""
        }
        return identityLabel(forSideIndex: index)
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

    private func nextPendingSetID(for exerciseOrder: Int) -> ActiveSetID? {
        config.exercises
            .first { $0.order == exerciseOrder }?
            .sets
            .filter { $0.state == .pending }
            .sorted { $0.index < $1.index }
            .first
            .flatMap(SessionCoordinator.activeSetID(for:))
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

/// The resting Superset side: a slim strip beneath the active card. Tapping it
/// brings its next pending Set up into the active card (matched-geometry morph).
private struct SupersetRestingStrip: View {
    let side: ActiveSupersetSidePresentation
    let identityLabel: String
    var isInteractive = true
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SupersetIdentityBadge(label: identityLabel, isActive: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(side.exerciseName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isInteractive {
                Image(systemName: "arrow.up.circle")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(palette.lastPerformedCardFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(palette.lastPerformedCardStroke.opacity(0.85), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.accessibilityLabel)
    }

    private var detailText: String {
        side.prescriptionText.isEmpty
            ? side.nextSetText
            : "\(side.nextSetText) · \(side.prescriptionText)"
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

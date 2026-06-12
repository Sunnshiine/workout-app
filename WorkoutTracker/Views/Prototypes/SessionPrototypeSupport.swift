// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import SwiftUI

/// The production Session View's animation-wrapped handlers, passed into
/// prototypes so every variant mutates through the same coordinator paths.
struct SessionPrototypeActions {
    let focus: (ExerciseSet) -> Void
    let log: (ExerciseSet, SetLog) -> Void
    let updateLoggedSet: (ExerciseSet, SetLog) -> Void
    let skip: (ExerciseSet) -> Void
    let delete: (ExerciseSet) -> Void
    let reexpand: (Exercise) -> Void
    let focusSupersetExercise: (Exercise) -> Void
    let dismissSuperset: (SessionSupersetRenderConfig) -> Void
    let moveOn: () -> Void
}

/// Mounts the selected prototype where the production scroll view would be,
/// keeping the shared header HUD and rest pill insets.
struct SessionPrototypeContainer<Header: View>: View {
    let variant: SessionPrototypeVariant
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
    let actions: SessionPrototypeActions
    @ViewBuilder let header: () -> Header

    var body: some View {
        variantBody
            .safeAreaInset(edge: .top, spacing: 0) {
                header()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if restTimer.isRunning {
                    RestPillView(restTimer: restTimer)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("session-prototype-\(variant.rawValue)")
    }

    @ViewBuilder
    private var variantBody: some View {
        switch variant {
        case .production:
            EmptyView()
        case .focusStack:
            SessionFocusStackPrototypeView(session: session, coordinator: coordinator, actions: actions)
        case .pager:
            SessionPagerPrototypeView(session: session, coordinator: coordinator, actions: actions)
        case .stage:
            SessionStagePrototypeView(session: session, coordinator: coordinator, actions: actions)
        case .rail:
            SessionRailPrototypeView(session: session, coordinator: coordinator, actions: actions)
        }
    }
}

/// A render item with the hidden paired entries dropped and the progress
/// readings every prototype needs (title, set states, next pending Set).
struct SessionPrototypeItem: Identifiable {
    let item: SessionRenderItem

    var id: String { item.id }

    var exercises: [Exercise] {
        switch item {
        case .exercise(let config): [config.exercise]
        case .superset(let config): config.exercises
        case .hiddenPairedExercise: []
        }
    }

    var title: String {
        switch item {
        case .exercise(let config): config.exercise.name
        case .superset(let config): config.exercises.map(\.baseName).joined(separator: " + ")
        case .hiddenPairedExercise: ""
        }
    }

    var shortTitle: String {
        switch item {
        case .exercise(let config): config.exercise.baseName
        case .superset: "Superset"
        case .hiddenPairedExercise: ""
        }
    }

    var sortedSets: [ExerciseSet] {
        exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }
            }
    }

    var completedSetCount: Int {
        sortedSets.filter { $0.state != .pending }.count
    }

    var isComplete: Bool {
        !sortedSets.contains { $0.state == .pending }
    }

    var progressText: String {
        "\(completedSetCount)/\(sortedSets.count)"
    }

    var nextPendingSet: ExerciseSet? {
        sortedSets.first { $0.state == .pending }
    }

    func contains(_ setID: ActiveSetID?) -> Bool {
        guard let setID else { return false }
        return exercises.contains { $0.order == setID.exerciseOrder }
    }
}

func sessionPrototypeItems(_ items: [SessionRenderItem]) -> [SessionPrototypeItem] {
    items.compactMap { item in
        if case .hiddenPairedExercise = item { return nil }
        return SessionPrototypeItem(item: item)
    }
}

/// One render item expanded to its full production surface — the unchanged
/// logging flow. Pairing creation (long-press) is intentionally not wired.
struct SessionPrototypeExpandedItem: View {
    let item: SessionPrototypeItem
    let actions: SessionPrototypeActions

    var body: some View {
        switch item.item {
        case .exercise(let config):
            ExerciseSection(
                config: config,
                onFocus: actions.focus,
                onReexpand: { actions.reexpand(config.exercise) },
                onLog: actions.log,
                onUpdateLoggedSet: actions.updateLoggedSet,
                onSkip: actions.skip,
                onDelete: actions.delete
            )
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
}

/// One dot per Set: filled accent when logged, dimmed when skipped, hollow when
/// pending. Optionally tappable with a ring marking the current Set.
struct SessionPrototypeSetDots: View {
    let sets: [ExerciseSet]
    var currentSetID: ActiveSetID?
    var dotSize: CGFloat = 6
    var onTap: ((ExerciseSet) -> Void)?
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(sets, id: \.persistentModelID) { set in
                if let onTap {
                    Button {
                        onTap(set)
                    } label: {
                        dot(for: set)
                            .padding(dotSize / 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set \(set.index + 1)")
                } else {
                    dot(for: set)
                }
            }
        }
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    @ViewBuilder
    private func dot(for set: ExerciseSet) -> some View {
        let isCurrent = currentSetID != nil && SessionCoordinator.activeSetID(for: set) == currentSetID
        Group {
            switch set.state {
            case .logged:
                Circle().fill(palette.accent)
            case .skipped:
                Circle().fill(Color.secondary.opacity(0.45))
            case .pending:
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(width: dotSize, height: dotSize)
        .overlay {
            if isCurrent {
                Circle()
                    .strokeBorder(palette.accent, lineWidth: 1.5)
                    .padding(-(dotSize / 2))
            }
        }
    }
}

/// Copy of the production Move On button (private to SessionView.swift).
struct SessionPrototypeMoveOnButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Move On", systemImage: "arrow.right")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.workoutGlass)
        .accessibilityHint("Advances to the next session")
        .accessibilityIdentifier("move-on-button")
    }
}

// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import SwiftUI

/// Stage: no list at all. The screen is a single "now playing" surface — the
/// Exercise name, its context, and the active Set card. Orientation is on
/// demand: an up-next hint at the bottom and the full queue in a sheet.
struct SessionStagePrototypeView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let actions: SessionPrototypeActions
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.themePalette) private var palette
    @State private var isQueuePresented = false

    var body: some View {
        let items = sessionPrototypeItems(
            coordinator.renderItems(in: session, lastPerformedLookup: lastPerformedLookup.snapshot)
        )
        let stageItem = stageItem(in: items)

        VStack(spacing: 0) {
            ScrollView {
                WorkoutGlassContainer(spacing: Theme.cardSpacing) {
                    Group {
                        if let stageItem {
                            stageContent(stageItem, items: items)
                        } else {
                            completion(items: items)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, Theme.sectionSpacing)
                    .padding(.bottom, Theme.cardSpacing)
                }
            }
            .scrollBounceBehavior(.always)
            .scrollEdgeEffectStyle(.soft, for: .top)

            queueBar(stageItem: stageItem, items: items)
        }
        .animation(Theme.momentumFlowAnimation, value: stageCardIdentity(in: items))
        .sheet(isPresented: $isQueuePresented) {
            queueSheet(stageItem: stageItem, items: items)
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stageContent(_ item: SessionPrototypeItem, items: [SessionPrototypeItem]) -> some View {
        switch item.item {
        case .exercise(let config):
            exerciseStage(config, position: position(of: item, in: items))
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

    private func exerciseStage(_ config: SessionExerciseRenderConfig, position: String) -> some View {
        let sortedSets = config.exercise.sets.sorted { $0.index < $1.index }

        return VStack(spacing: 14) {
            Text(position)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(config.exercise.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            if let note = config.exercise.coachNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SessionPrototypeSetDots(
                sets: sortedSets,
                currentSetID: config.activeSetID,
                dotSize: 9,
                onTap: actions.focus
            )
            .padding(.vertical, 2)

            if let lastPerformed = config.lastPerformedPresentation {
                LastPerformedCard(presentation: lastPerformed)
            }

            stageCard(config, sortedSets: sortedSets)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stageCard(_ config: SessionExerciseRenderConfig, sortedSets: [ExerciseSet]) -> some View {
        if let expandedID = config.expandedLoggedSetID,
            let set = sortedSets.first(where: { SessionCoordinator.activeSetID(for: $0) == expandedID }) {
            LoggedSetReviewCard(
                set: set,
                setOrdinal: ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                showsSavedConfirmation: expandedID == config.savedLoggedSetID,
                onCommit: { actions.updateLoggedSet(set, $0) },
                onCollapse: { actions.focus(set) }
            )
            .id("stage-review-\(expandedID.exerciseOrder)-\(expandedID.setIndex)")
            .transition(.push(from: .bottom))
        } else if let set = stageSet(config, sortedSets: sortedSets) {
            ActiveSetCard(
                exercise: config.exercise,
                set: set,
                setOrdinal: ordinal(of: set, in: sortedSets),
                setCount: sortedSets.count,
                onLog: { actions.log(set, $0) },
                onSkip: { actions.skip(set) },
                onDelete: { actions.delete(set) }
            )
            .id("stage-active-\(config.exercise.order)-\(set.index)")
            .transition(.push(from: .bottom))
        }
    }

    /// The Set on stage: the coordinator's active Set, else the next pending one.
    private func stageSet(_ config: SessionExerciseRenderConfig, sortedSets: [ExerciseSet]) -> ExerciseSet? {
        if let activeID = config.activeSetID,
            let set = sortedSets.first(where: { SessionCoordinator.activeSetID(for: $0) == activeID }) {
            return set
        }
        return sortedSets.first { $0.state == .pending }
    }

    private func completion(items: [SessionPrototypeItem]) -> some View {
        let loggedSets = items.reduce(0) { $0 + $1.completedSetCount }

        return VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(palette.accent)

            Text("Session complete")
                .font(.title2.weight(.bold))

            Text("\(loggedSets) sets done across \(items.count) exercises")
                .font(.callout)
                .foregroundStyle(.secondary)

            if workout.isViewingLiveEdge, workout.canMoveOn {
                SessionPrototypeMoveOnButton(onTap: actions.moveOn)
                    .padding(.top, Theme.cardSpacing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.sectionSpacing)
    }

    // MARK: - Queue

    private func queueBar(stageItem: SessionPrototypeItem?, items: [SessionPrototypeItem]) -> some View {
        let upNext = upNextItem(after: stageItem, in: items)
        let completedCount = items.filter(\.isComplete).count

        return HStack(spacing: 12) {
            if let upNext {
                Button {
                    jump(to: upNext)
                } label: {
                    HStack(spacing: 8) {
                        Text("Up next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .textCase(.uppercase)

                        Text(upNext.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .workoutGlass(.capsule)
                .accessibilityIdentifier("stage-up-next")
            }

            Spacer(minLength: 0)

            Button {
                isQueuePresented = true
            } label: {
                Label("\(completedCount) of \(items.count)", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.workoutGlass)
            .accessibilityIdentifier("stage-queue-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func queueSheet(stageItem: SessionPrototypeItem?, items: [SessionPrototypeItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Session")
                    .font(.headline)
                    .padding(.top, 18)

                ForEach(items) { item in
                    queueRow(for: item, isOnStage: item.id == stageItem?.id)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func queueRow(for item: SessionPrototypeItem, isOnStage: Bool) -> some View {
        Button {
            jump(to: item)
            isQueuePresented = false
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isComplete ? .secondary : .primary)
                        .lineLimit(1)

                    SessionPrototypeSetDots(sets: item.sortedSets)
                }

                Spacer(minLength: 12)

                if isOnStage {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                } else if item.isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isComplete)
        .accessibilityIdentifier("stage-queue-row-\(item.id)")
    }

    // MARK: - Resolution

    private func stageItem(in items: [SessionPrototypeItem]) -> SessionPrototypeItem? {
        let focusID = coordinator.visualFocusOwner?.setID ?? coordinator.activeSetID
        if let item = items.first(where: { $0.contains(focusID) }) {
            return item
        }
        return items.first { !$0.isComplete }
    }

    private func stageCardIdentity(in items: [SessionPrototypeItem]) -> String {
        let focusID = coordinator.visualFocusOwner?.setID ?? coordinator.activeSetID
        guard let focusID else { return stageItem(in: items)?.id ?? "complete" }
        return "\(focusID.exerciseOrder)-\(focusID.setIndex)"
    }

    private func upNextItem(
        after stageItem: SessionPrototypeItem?,
        in items: [SessionPrototypeItem]
    ) -> SessionPrototypeItem? {
        guard let stageItem else { return nil }
        let pending = items.filter { !$0.isComplete && $0.id != stageItem.id }
        if let stageIndex = items.firstIndex(where: { $0.id == stageItem.id }),
            let next = items[items.index(after: stageIndex)...].first(where: { !$0.isComplete }) {
            return next
        }
        return pending.first
    }

    private func position(of item: SessionPrototypeItem, in items: [SessionPrototypeItem]) -> String {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return "" }
        return "Exercise \(index + 1) of \(items.count)"
    }

    private func ordinal(of set: ExerciseSet, in sortedSets: [ExerciseSet]) -> Int {
        (sortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }

    private func jump(to item: SessionPrototypeItem) {
        guard let nextSet = item.nextPendingSet else { return }
        actions.focus(nextSet)
    }
}

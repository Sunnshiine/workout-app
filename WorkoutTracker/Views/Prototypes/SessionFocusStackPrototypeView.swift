// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import SwiftUI

/// Focus Stack: the familiar vertical list, but only one Exercise is expanded at
/// a time — every other Exercise is a slim glass row with set-progress dots.
/// Tapping a row brings it into focus; logging momentum moves focus forward.
struct SessionFocusStackPrototypeView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let actions: SessionPrototypeActions
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @State private var manualFocusItemID: String?

    var body: some View {
        let items = sessionPrototypeItems(
            coordinator.renderItems(in: session, lastPerformedLookup: lastPerformedLookup.snapshot)
        )
        let focusedID = focusedItemID(in: items)

        ScrollViewReader { proxy in
            ScrollView {
                WorkoutGlassContainer(spacing: Theme.cardSpacing) {
                    VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                        ForEach(items) { item in
                            row(for: item, isFocused: item.id == focusedID)
                                .id(item.id)
                        }

                        if workout.isViewingLiveEdge, workout.canMoveOn {
                            SessionPrototypeMoveOnButton(onTap: actions.moveOn)
                                .padding(.top, Theme.cardSpacing)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
            }
            .scrollBounceBehavior(.always)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: coordinator.activeSetID) { _, newValue in
                followCoordinatorFocus(newValue, items: items, proxy: proxy)
            }
        }
        .animation(Theme.focusMorphAnimation, value: focusedID)
    }

    @ViewBuilder
    private func row(for item: SessionPrototypeItem, isFocused: Bool) -> some View {
        if isFocused {
            SessionPrototypeExpandedItem(item: item, actions: actions)
        } else {
            collapsedRow(for: item)
        }
    }

    private func collapsedRow(for item: SessionPrototypeItem) -> some View {
        Button {
            select(item)
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

                Text(item.progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .workoutGlass(.card)
        .accessibilityIdentifier("focus-stack-collapsed-\(item.id)")
    }

    private func select(_ item: SessionPrototypeItem) {
        manualFocusItemID = item.id
        if let nextSet = item.nextPendingSet {
            actions.focus(nextSet)
        } else if case .exercise(let config) = item.item, config.isCollapsed {
            actions.reexpand(config.exercise)
        }
    }

    private func focusedItemID(in items: [SessionPrototypeItem]) -> String? {
        if let manualFocusItemID, items.contains(where: { $0.id == manualFocusItemID }) {
            return manualFocusItemID
        }
        if let active = items.first(where: { $0.contains(coordinator.activeSetID) }) {
            return active.id
        }
        return items.first { !$0.isComplete }?.id
    }

    private func followCoordinatorFocus(
        _ activeSetID: ActiveSetID?,
        items: [SessionPrototypeItem],
        proxy: ScrollViewProxy
    ) {
        guard let target = items.first(where: { $0.contains(activeSetID) }) else { return }
        if manualFocusItemID != target.id {
            manualFocusItemID = nil
        }
        withAnimation(Theme.momentumFlowAnimation) {
            proxy.scrollTo(target.id, anchor: .top)
        }
    }
}

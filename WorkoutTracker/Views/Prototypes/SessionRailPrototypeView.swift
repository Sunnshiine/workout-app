// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import SwiftUI

/// Rail: a horizontal chip rail keeps the whole Session glanceable in one line
/// while the area below holds exactly one expanded Exercise. Orientation and
/// focus live in different axes, so neither crowds the other.
struct SessionRailPrototypeView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let actions: SessionPrototypeActions
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.themePalette) private var palette
    @State private var manualFocusItemID: String?

    var body: some View {
        let items = sessionPrototypeItems(
            coordinator.renderItems(in: session, lastPerformedLookup: lastPerformedLookup.snapshot)
        )
        let focusedID = focusedItemID(in: items)

        VStack(spacing: 0) {
            chipRail(items: items, focusedID: focusedID)

            ScrollView {
                WorkoutGlassContainer(spacing: Theme.cardSpacing) {
                    VStack(spacing: Theme.cardSpacing) {
                        if let focused = items.first(where: { $0.id == focusedID }) {
                            SessionPrototypeExpandedItem(item: focused, actions: actions)
                                .id(focused.id)
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
        }
        .onChange(of: coordinator.activeSetID) { _, newValue in
            guard let target = items.first(where: { $0.contains(newValue) }) else { return }
            if manualFocusItemID != target.id {
                manualFocusItemID = nil
            }
        }
        .animation(Theme.focusMorphAnimation, value: focusedID)
    }

    private func chipRail(items: [SessionPrototypeItem], focusedID: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        chip(for: item, isCurrent: item.id == focusedID)
                            .id(item.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("rail-chip-rail")
            .onAppear {
                if let focusedID {
                    proxy.scrollTo(focusedID, anchor: .center)
                }
            }
            .onChange(of: focusedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(Theme.focusMorphAnimation) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func chip(for item: SessionPrototypeItem, isCurrent: Bool) -> some View {
        Button {
            select(item)
        } label: {
            HStack(spacing: 6) {
                Text(item.shortTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isComplete && !isCurrent ? .secondary : .primary)
                    .lineLimit(1)

                if item.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                } else {
                    Text(item.progressText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .workoutGlass(.capsule)
        .overlay {
            if isCurrent {
                Capsule()
                    .strokeBorder(palette.accent, lineWidth: 1.5)
            }
        }
        .accessibilityIdentifier("rail-chip-\(item.id)")
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
        return items.first { !$0.isComplete }?.id ?? items.last?.id
    }
}

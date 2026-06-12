// PROTOTYPE — throwaway. Session View layout lab; see docs/prototypes/session-view-prototypes.md.
import SwiftUI

/// Pager: one Exercise per horizontal page with snap paging — the rest of the
/// Session physically can't crowd the screen. Logging auto-advances the page;
/// a calm summary page with Move On closes the deck.
struct SessionPagerPrototypeView: View {
    let session: Session
    let coordinator: SessionCoordinator
    let actions: SessionPrototypeActions
    @Environment(WorkoutStore.self) private var workout
    @Environment(LastPerformedLookupStore.self) private var lastPerformedLookup
    @Environment(\.themePalette) private var palette
    @State private var pageID: String?

    private static let summaryPageID = "pager-summary"

    var body: some View {
        let items = sessionPrototypeItems(
            coordinator.renderItems(in: session, lastPerformedLookup: lastPerformedLookup.snapshot)
        )

        VStack(spacing: 0) {
            pageIndicator(items: items)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(items) { item in
                        page(for: item)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }

                    summaryPage(items: items)
                        .containerRelativeFrame(.horizontal)
                        .id(Self.summaryPageID)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageID)
            .scrollIndicators(.hidden)
        }
        .onAppear {
            pageID = initialPageID(items: items)
        }
        .onChange(of: coordinator.activeSetID) { _, newValue in
            guard
                let target = items.first(where: { $0.contains(newValue) }),
                target.id != pageID
            else { return }
            withAnimation(Theme.momentumFlowAnimation) {
                pageID = target.id
            }
        }
    }

    private func page(for item: SessionPrototypeItem) -> some View {
        ScrollView {
            WorkoutGlassContainer(spacing: Theme.cardSpacing) {
                SessionPrototypeExpandedItem(item: item, actions: actions)
                    .padding(.horizontal)
                    .padding(.vertical)
            }
        }
        .scrollBounceBehavior(.always)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func pageIndicator(items: [SessionPrototypeItem]) -> some View {
        HStack(spacing: 7) {
            ForEach(items) { item in
                indicatorDot(
                    isCurrent: item.id == pageID,
                    isComplete: item.isComplete
                ) {
                    jump(to: item.id)
                }
            }

            indicatorDot(
                isCurrent: pageID == Self.summaryPageID,
                isComplete: false
            ) {
                jump(to: Self.summaryPageID)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .workoutGlass(.capsule)
        .accessibilityIdentifier("pager-page-indicator")
    }

    private func indicatorDot(isCurrent: Bool, isComplete: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Capsule()
                .fill(dotColor(isCurrent: isCurrent, isComplete: isComplete))
                .frame(width: isCurrent ? 18 : 7, height: 7)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.focusMorphAnimation, value: isCurrent)
    }

    private func dotColor(isCurrent: Bool, isComplete: Bool) -> Color {
        if isCurrent { return palette.accent }
        if isComplete { return palette.accent.opacity(0.45) }
        return Color.secondary.opacity(0.4)
    }

    private func summaryPage(items: [SessionPrototypeItem]) -> some View {
        let totalSets = items.reduce(0) { $0 + $1.sortedSets.count }
        let completedSets = items.reduce(0) { $0 + $1.completedSetCount }

        return ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                VStack(spacing: 8) {
                    Text(completedSets == totalSets ? "Session complete" : "Almost there")
                        .font(.title2.weight(.bold))
                    Text("\(completedSets) of \(totalSets) sets done")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Theme.sectionSpacing)

                VStack(spacing: 10) {
                    ForEach(items) { item in
                        summaryRow(for: item)
                    }
                }

                if workout.isViewingLiveEdge, workout.canMoveOn {
                    SessionPrototypeMoveOnButton(onTap: actions.moveOn)
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .scrollBounceBehavior(.always)
    }

    private func summaryRow(for item: SessionPrototypeItem) -> some View {
        Button {
            jump(to: item.id)
        } label: {
            HStack(spacing: 12) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                SessionPrototypeSetDots(sets: item.sortedSets)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .workoutGlass(.card)
    }

    private func initialPageID(items: [SessionPrototypeItem]) -> String? {
        if let active = items.first(where: { $0.contains(coordinator.activeSetID) }) {
            return active.id
        }
        return items.first { !$0.isComplete }?.id ?? Self.summaryPageID
    }

    private func jump(to id: String) {
        withAnimation(Theme.momentumFlowAnimation) {
            pageID = id
        }
    }
}

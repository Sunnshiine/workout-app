import SwiftUI

extension DynamicTypeSize {
    /// From here the island has no height for the corners as well as the Set's two lines and the
    /// chips, so the corners give way: the countdown, which the compact island and the Lock Screen
    /// still count, and the queue, which moves down beside the target.
    var islandShedsTheCorners: Bool { self >= .xxLarge }
}

/// A corner of the expanded island during a rest, empty where the type leaves it no room.
struct IslandRestCorner<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: Content

    var body: some View {
        if !typeSize.islandShedsTheCorners {
            content
        }
    }
}

/// What the island's Set lines try, in order, until one fits the island's width at the reader's type
/// size. The guidance gives way first, then the target moves down under the name, and last the name
/// cuts off in the middle and the target shrinks, then cuts off, so a long cell never pushes the
/// queue, the mic, or a chip off the island.
enum IslandOfferFit: CaseIterable {
    case targetBesideTheName
    case targetUnderTheName
    case nameAndTargetGiveWay

    var targetOnTheSetLine: Bool { self == .targetBesideTheName }
    var nameAndTargetGiveWay: Bool { self == .nameAndTargetGiveWay }
}

/// The Set under the countdown, over how to log it, since nothing else on the island names the
/// Exercise a press logs to. Under the set line, the Cadence and Coach Note cut off with "…".
struct IslandSetOffer: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The narrowest cut of the guidance worth drawing, about a word and its "…".
    @ScaledMetric(relativeTo: .footnote) private var guidanceStub: CGFloat = 56

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                // The island drew a truncating name short of the room beside it, so the first two
                // candidates hold the name at its own width, and only the last lets it cut off.
                ViewThatFits(in: .horizontal) {
                    ForEach(IslandOfferFit.allCases, id: \.self) { fit in
                        lines(fit)
                    }
                }
                .accessibilityElement(children: .combine)

                // The Start in the mic's place for a Set that opens on a timed effort.
                if let start = state.start {
                    LockScreenStartButton(start: start, colors: colors, diameter: 44)
                } else {
                    SaySetButton(state: state, diameter: 44)
                }
            }

            switch state.loggablePress {
            case .ready(let offer):
                LockScreenChipRow(
                    offer: offer,
                    weight: state.weightText,
                    labelColor: colors.islandPrimaryText,
                    colors: colors,
                    spacing: 6,
                    chipHeight: LockScreenCardMetrics.controlSize
                )
            case .needsApp:
                Link(destination: LockScreenChipRow.appURL) {
                    Text("Open to log")
                        .liveActivityFont(.control)
                        .foregroundStyle(colors.islandPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: LockScreenCardMetrics.controlSize)
                        .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                        .contentShape(.rect)
                }
            }
        }
    }

    private func lines(_ fit: IslandOfferFit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            setLine(withTheTarget: fit.targetOnTheSetLine, nameFits: !fit.nameAndTargetGiveWay)
            guidanceLine(withTheTarget: !fit.targetOnTheSetLine, targetGivesWay: fit.nameAndTargetGiveWay)
        }
    }

    /// The target when the set line had no room for it, the queue when the corners gave way, then
    /// the guidance. The guidance cuts off first, then a target that gives way, and the queue never.
    @ViewBuilder
    private func guidanceLine(withTheTarget: Bool, targetGivesWay: Bool) -> some View {
        let target = withTheTarget ? state.prescriptionText : nil
        let queue = typeSize.islandShedsTheCorners ? state.pendingWritesText : nil
        if target != nil || queue != nil || state.guidance != nil {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let target {
                    Text(target)
                        .liveActivityFont(.label)
                        .lineLimit(1)
                        .minimumScaleFactor(targetGivesWay ? LockScreenCardMetrics.targetFloorScale : 1)
                        .fixedSize(horizontal: !targetGivesWay, vertical: false)
                        .layoutPriority(1)
                }

                if let queue {
                    Text(target == nil ? queue : " · \(queue)")
                        .liveActivityFont(.label)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(2)
                }

                if let guidance = state.guidance {
                    let text = Text(target == nil && queue == nil ? guidance : " · \(guidance)")
                        .liveActivityFont(.guidance)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // A stub too short to read draws nothing, and the guidance's width never decides
                    // which of the set line's candidates fits.
                    ViewThatFits(in: .horizontal) {
                        text.fixedSize()
                        text.frame(minWidth: guidanceStub, idealWidth: guidanceStub, maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(state.liveActivityColors.islandSecondaryText)
        }
    }

    private func setLine(withTheTarget: Bool, nameFits: Bool) -> some View {
        let colors = state.liveActivityColors

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state.exerciseName)
                .liveActivityFont(.exerciseName)
                .foregroundStyle(colors.islandPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(nameFits ? 1 : 0.8)
                .truncationMode(.middle)
                .fixedSize(horizontal: nameFits, vertical: false)
                .layoutPriority(1)

            if !state.weightText.isEmpty {
                SelectedWeightText(state: state, color: colors.islandPrimaryText)
                    .liveActivityFont(.figure)
                    .fixedSize()
            }

            if withTheTarget {
                Text(state.prescriptionText)
                    .liveActivityFont(.label)
                    .foregroundStyle(colors.islandSecondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
    }
}

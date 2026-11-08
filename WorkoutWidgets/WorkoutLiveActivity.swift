import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    /// DESIGN.md's Product Scale Rule: app-drawn text stops growing here.
    fileprivate static let largestType = DynamicTypeSize.xxxLarge

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state)
                .activityBackgroundTint(context.state.liveActivityColors.background)
                .activitySystemActionForegroundColor(context.state.liveActivityColors.action)
        } dynamicIsland: { context in
            DynamicIsland {
                expandedContent(for: context)
            } compactLeading: {
                compactLeading(for: context.state)
            } compactTrailing: {
                compactTrailing(for: context.state)
            } minimal: {
                minimalContent(for: context.state)
            }
            .keylineTint(context.state.liveActivityColors.action)
            // At the default margin, about 18pt, the expanded island's rounded corners cut glyphs.
            .contentMargins(.horizontal, 34, for: .expanded)
        }
    }

    @DynamicIslandExpandedContentBuilder
    private func expandedContent(
        for context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> DynamicIslandExpandedContent<some View> {
        DynamicIslandExpandedRegion(.leading) {
            expandedLeading(for: context.state)
                .dynamicTypeSize(...Self.largestType)
        }
        DynamicIslandExpandedRegion(.trailing) {
            expandedTrailing(for: context.state)
                .dynamicTypeSize(...Self.largestType)
        }
        DynamicIslandExpandedRegion(.center) {
            expandedCenter(for: context)
                .dynamicTypeSize(...Self.largestType)
        }
        DynamicIslandExpandedRegion(.bottom) {
            expandedBottom(for: context)
                .dynamicTypeSize(...Self.largestType)
        }
    }

    @ViewBuilder
    private func expandedLeading(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            // A write's content is the rest toward the next Set, whose prescription is not the
            // written Set's.
            if dictation.isAboutASet, dictation.writtenSet == nil {
                PrescriptionStack(state: state)
                    .lineLimit(1)
            }
        } else {
            switch state.variant {
            case .setProgress:
                SetProgressBadge(state: state)
            case .nowLifting:
                SetProgressRing(state: state, lineWidth: 4)
                    .frame(width: 42, height: 42)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                restLeading(for: state)
            }
        }
    }

    /// The countdown and the queue sit in the corners beside the camera, and the centre stays empty,
    /// so the island's bottom has the room for the set line, the guidance, and the chips.
    private func restLeading(for state: WorkoutActivityAttributes.ContentState) -> some View {
        IslandRestCorner {
            RestCountdownStack(state: state, showsLabel: false, digits: .figure)
        }
    }

    /// The queue shrinks rather than wrap, because a wrap at the largest type set the count above
    /// its word.
    private func restTrailing(for state: WorkoutActivityAttributes.ContentState) -> some View {
        IslandRestCorner {
            if let queue = state.pendingWritesText {
                Text(queue)
                    .liveActivityFont(.label)
                    .foregroundStyle(state.liveActivityColors.islandSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private func expandedTrailing(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            if dictation.isListening {
                DictationSymbol(dictation: dictation, colors: state.liveActivityColors, diameter: 44)
            } else if dictation.isAboutASet {
                SaySetButton(state: state, diameter: 44)
            }
        } else {
            switch state.variant {
            case .setProgress, .nowLifting:
                PrescribedLoadBadge(state: state)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                restTrailing(for: state)
            }
        }
    }

    @ViewBuilder
    private func expandedCenter(
        for context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        if let dictation = context.state.dictation {
            DictationReadback(dictation: dictation, colors: context.state.liveActivityColors, style: .island)
        } else {
            switch context.state.variant {
            case .setProgress:
                ExerciseNameStack(state: context.state)
            case .nowLifting:
                WeightForwardStack(state: context.state)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(
        for context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
        if let dictation = context.state.dictation {
            if dictation.isAboutASet || context.state.restEndDate != nil {
                DictationProgress(state: context.state, dictation: dictation, style: .island)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch context.state.variant {
            case .setProgress:
                SegmentedSets(
                    done: context.state.setsDone,
                    total: context.state.setsTotal,
                    colors: context.state.liveActivityColors
                )
                .padding(.top, 2)
            case .nowLifting:
                ExerciseNameStack(state: context.state)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                IslandSetOffer(state: context.state)
            }
        }
    }

    @ViewBuilder
    private func compactLeading(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            Image(systemName: dictation.symbolName)
                .foregroundStyle(state.liveActivityColors.readbackText(dictation.tone, onIsland: true))
        } else {
            switch state.variant {
            case .setProgress:
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(state.liveActivityColors.action)
            case .nowLifting:
                SetProgressRing(state: state, lineWidth: 3)
                    .frame(width: 22, height: 22)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                Image(systemName: "timer")
                    .foregroundStyle(state.liveActivityColors.action)
            }
        }
    }

    @ViewBuilder
    private func compactTrailing(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            Text(dictation.compactText)
                .font(.caption.weight(.heavy))
                .foregroundStyle(state.liveActivityColors.readbackText(dictation.tone, onIsland: true))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            switch state.variant {
            case .setProgress:
                Text(state.setProgressText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(state.liveActivityColors.islandPrimaryText)
                    .monospacedDigit()
            case .nowLifting:
                Text(state.weightValue)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(state.liveActivityColors.actionInk)
                    .minimumScaleFactor(0.75)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                RestCountdownText(state: state)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(state.liveActivityColors.actionInk)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func minimalContent(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            Image(systemName: dictation.symbolName)
                .foregroundStyle(state.liveActivityColors.readbackText(dictation.tone, onIsland: true))
        } else {
            switch state.variant {
            case .setProgress:
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(state.liveActivityColors.action)
            case .nowLifting:
                SetProgressRing(state: state, lineWidth: 3)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                Image(systemName: "timer")
                    .foregroundStyle(state.liveActivityColors.action)
            }
        }
    }
}

private struct LockScreenWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let dictation = state.dictation {
                if dictation.isAboutASet {
                    DictationLockScreenView(state: state, dictation: dictation)
                } else {
                    NoSetLockScreenView(state: state, dictation: dictation)
                }
            } else if state.variant.isRestTimer {
                SetOfferLockScreenView(state: state)
            } else {
                progress
            }
        }
        .animation(.smooth(duration: 0.35), value: state.dictation)
        .dynamicTypeSize(...WorkoutLiveActivity.largestType)
    }

    private var progress: some View {
        let colors = state.liveActivityColors

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(state.exerciseName)
                    .liveActivityFont(.exerciseName)
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                SegmentedSets(done: state.setsDone, total: state.setsTotal, colors: colors)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                Text(state.weightValue)
                    .liveActivityFont(.largeFigure)
                    .foregroundStyle(colors.actionInk)

                Text(state.weightUnit)
                    .liveActivityFont(.label)
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(16)
    }
}

extension DynamicTypeSize {
    /// From here the island has no height for the corners as well as the Set's two lines and the
    /// chips, so the corners give way: the countdown, which the compact island and the Lock Screen
    /// still count, and the queue, which moves down beside the target.
    fileprivate var islandShedsTheCorners: Bool { self >= .xxLarge }
}

/// A corner of the expanded island during a rest, empty where the type leaves it no room.
private struct IslandRestCorner<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: Content

    var body: some View {
        if !typeSize.islandShedsTheCorners {
            content
        }
    }
}

/// The Set under the countdown, over how to log it, since nothing else on the island names the
/// Exercise a press logs to. Under the set line, the Cadence and Coach Note cut off with "…". A
/// target the set line has no room for moves down ahead of them, so the guidance gives way first and
/// the target never does.
private struct IslandSetOffer: View {
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
                    lines(targetOnTheSetLine: true, nameFits: true)
                    lines(targetOnTheSetLine: false, nameFits: true)
                    lines(targetOnTheSetLine: false, nameFits: false)
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

    private func lines(targetOnTheSetLine: Bool, nameFits: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            setLine(withTheTarget: targetOnTheSetLine, nameFits: nameFits)
            guidanceLine(withTheTarget: !targetOnTheSetLine)
        }
    }

    /// The target when the set line had no room for it, the queue when the corners gave way, then
    /// the guidance. Only the guidance cuts off.
    @ViewBuilder
    private func guidanceLine(withTheTarget: Bool) -> some View {
        let whole = [
            withTheTarget ? state.prescriptionText : nil,
            typeSize.islandShedsTheCorners ? state.pendingWritesText : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        if !whole.isEmpty || state.guidance != nil {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !whole.isEmpty {
                    Text(whole)
                        .liveActivityFont(.label)
                        .lineLimit(1)
                        .fixedSize()
                }

                if let guidance = state.guidance {
                    let text = Text(whole.isEmpty ? guidance : " · \(guidance)")
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

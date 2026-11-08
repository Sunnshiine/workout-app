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

    /// The chips' line and tick state the prescription, so this keeps only what they leave out.
    @ViewBuilder
    private func restLeading(for state: WorkoutActivityAttributes.ContentState) -> some View {
        switch state.loggablePress {
        case .ready(let offer):
            if let prescription = state.prescription(beyond: offer) {
                Text(prescription)
                    .liveActivityFont(.label)
                    .foregroundStyle(state.liveActivityColors.islandSecondaryText)
                    .lineLimit(2)
            }
        case .needsApp:
            // A long load shrinks to fit, since a prescription cut off mid-value reads wrong.
            PrescriptionStack(state: state)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                SaySetButton(state: state, diameter: 44)
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
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount:
                // The chips' Exercise and values read under it, so the digits need no label, and
                // the chips take the room the digits would.
                if context.state.loggablePress == .needsApp {
                    IslandRestCountdown(state: context.state)
                } else {
                    RestCountdownStack(state: context.state, showsLabel: false, digits: .figure)
                }
            case .restTimerClean:
                RestCountdownStack(state: context.state, showsLabel: false, digits: .largeFigure)
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
        } else if context.state.variant.isRestTimer, case .ready(let offer) = context.state.loggablePress {
            IslandRPEChips(state: context.state, offer: offer)
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
            case .restTimer, .restTimerClean:
                RestProgressBar(state: context.state, fill: context.state.liveActivityColors.islandSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .restTimerSetsLeft, .restTimerSetCount:
                RestProgressWithContext(state: context.state, style: .island)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// The rest with no chips under it. The system gives the expanded island's center the height it asks
/// for and takes it from the row under it, so space cannot decide what gives way here: at the
/// largest type the label goes, and the count of Sets left under it stays whole.
private struct IslandRestCountdown: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RestCountdownStack(state: state, showsLabel: dynamicTypeSize < WorkoutLiveActivity.largestType, digits: .largeFigure)
    }
}

/// The Exercise and what a chip logs, over the chips, since nothing else on the island names the
/// Exercise a press logs to. The island's own lines name the prescription.
private struct IslandRPEChips: View {
    let state: WorkoutActivityAttributes.ContentState
    let offer: LoggablePress.Offer

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                setLine(beside: state.pendingWritesText ?? state.restContextText)
                setLine(beside: nil)
            }
            .accessibilityElement(children: .combine)

            RPEChipRow(offer: offer, labelColor: colors.islandPrimaryText, colors: colors, spacing: 4, chipHeight: 44)
        }
    }

    /// The count gives way before the name, which says what a press logs to.
    private func setLine(beside count: String?) -> some View {
        let colors = state.liveActivityColors

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state.exerciseName)
                .liveActivityFont(.exerciseName)
                .foregroundStyle(colors.islandPrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            LoggableValuesText(offer: offer, color: colors.islandPrimaryText)
                .liveActivityFont(.figure)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            if let count {
                Text(count)
                    .liveActivityFont(.label)
                    .foregroundStyle(colors.islandSecondaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
    }
}

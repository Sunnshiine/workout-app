import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state)
                .activityBackgroundTint(context.state.liveActivityColors.background)
                .activitySystemActionForegroundColor(context.state.liveActivityColors.accent)
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
            .keylineTint(context.state.liveActivityColors.accent)
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
        }
        DynamicIslandExpandedRegion(.trailing) {
            expandedTrailing(for: context.state)
        }
        DynamicIslandExpandedRegion(.center) {
            expandedCenter(for: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
            expandedBottom(for: context)
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
                PrescriptionStack(state: state)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func expandedTrailing(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            if dictation.isListening {
                DictationSymbol(dictation: dictation, colors: state.liveActivityColors, diameter: 40)
            } else if dictation.isAboutASet {
                SaySetLink(state: state, diameter: 40)
            }
        } else {
            switch state.variant {
            case .setProgress, .nowLifting:
                PrescribedLoadBadge(state: state)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                SaySetLink(state: state, diameter: 40)
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
                RestCountdownStack(state: context.state)
            case .restTimerClean:
                RestCountdownStack(state: context.state, showsLabel: false)
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
            case .restTimer, .restTimerClean:
                RestProgressBar(state: context.state)
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
                    .foregroundStyle(state.liveActivityColors.accent)
            case .nowLifting:
                SetProgressRing(state: state, lineWidth: 3)
                    .frame(width: 22, height: 22)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                Image(systemName: "timer")
                    .foregroundStyle(state.liveActivityColors.accent)
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
                    .foregroundStyle(state.liveActivityColors.accent)
                    .minimumScaleFactor(0.75)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                RestCountdownText(state: state)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(state.liveActivityColors.accent)
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
                    .foregroundStyle(state.liveActivityColors.accent)
            case .nowLifting:
                SetProgressRing(state: state, lineWidth: 3)
            case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
                Image(systemName: "timer")
                    .foregroundStyle(state.liveActivityColors.accent)
            }
        }
    }
}

private struct LockScreenWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let dictation = state.dictation {
            if dictation.isAboutASet {
                DictationLockScreenView(state: state, dictation: dictation)
            } else {
                NoSetLockScreenView(state: state, dictation: dictation)
            }
        } else {
            restOrProgress
        }
    }

    private var restOrProgress: some View {
        let colors = state.liveActivityColors

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.exerciseName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if state.variant.isRestTimer {
                        RestCountdownText(state: state)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(colors.accent)
                            .monospacedDigit()

                        RestProgressBar(state: state)

                        if state.restContextText != nil {
                            RestProgressWithContext(state: state, style: .lockScreen, showsBar: false)
                        }
                    } else {
                        SegmentedSets(done: state.setsDone, total: state.setsTotal, colors: colors)
                    }
                }

                Spacer(minLength: 10)

                if state.variant.isRestTimer {
                    PrescriptionStack(state: state, style: .lockScreen)
                        .minimumScaleFactor(0.75)

                    SaySetLink(state: state, diameter: 44)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(state.weightValue)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(colors.accent)
                            .monospacedDigit()

                        Text(state.weightUnit)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(colors.secondaryText)
                    }
                }
            }
        }
        .padding(16)
    }
}

/// The Lock Screen while a Dictation the athlete ran without the app listens for the Set, and
/// once it has an answer: the readback under the Exercise of the Set it is about, over the rest
/// when a logged Set began one, else over the Exercise's Sets.
private struct DictationLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let dictation: LiveActivityDictation

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dictation.writtenSet?.exerciseName ?? state.exerciseName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    DictationReadback(dictation: dictation, colors: colors, style: .lockScreen)
                }

                Spacer(minLength: 10)

                if dictation.writtenSet == nil {
                    PrescriptionStack(state: state, style: .lockScreen)
                        .minimumScaleFactor(0.75)
                }

                if dictation.isListening {
                    DictationSymbol(dictation: dictation, colors: colors, diameter: 44)
                } else {
                    SaySetLink(state: state, diameter: 44)
                }
            }

            DictationProgress(state: state, dictation: dictation, style: .lockScreen)
        }
        .padding(16)
    }
}

/// The Lock Screen when a press found no Set to listen for: the Session it looked in, if any, over
/// why, and the rest countdown when one is running.
private struct NoSetLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let dictation: LiveActivityDictation

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if let session = dictation.sessionName {
                    Text(session)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                }

                DictationReadback(dictation: dictation, colors: colors, style: .lockScreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.restEndDate != nil {
                DictationProgress(state: state, dictation: dictation, style: .lockScreen)
            }
        }
        .padding(16)
    }
}

private struct DictationReadback: View {
    enum Style {
        case island
        case lockScreen
    }

    let dictation: LiveActivityDictation
    let colors: LiveActivityColors
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dictation.headline)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(colors.readbackText(dictation.tone, onIsland: style == .island))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let detail {
                Text(detail)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live-activity-dictation")
    }

    /// The island has no line naming the Exercise, so a write's detail names it.
    private var detail: String? {
        guard style == .island, let set = dictation.writtenSet else { return dictation.detail }
        return set.fullText
    }

    private var secondaryTextColor: Color {
        switch style {
        case .island: colors.islandSecondaryText
        case .lockScreen: colors.secondaryText
        }
    }
}

/// The mic while listening, where the Say Set link sits otherwise.
private struct DictationSymbol: View {
    let dictation: LiveActivityDictation
    let colors: LiveActivityColors
    let diameter: CGFloat

    var body: some View {
        let symbol = colors.readbackSymbol(dictation.tone)
        Image(systemName: dictation.symbolName)
            .font(.system(size: diameter * 0.45, weight: .semibold))
            .foregroundStyle(symbol.glyph)
            .frame(width: diameter, height: diameter)
            .background(symbol.circle, in: Circle())
            .accessibilityLabel(dictation.headline)
    }
}

/// The rest countdown when a logged Set began one, else the Exercise's Sets.
private struct DictationProgress: View {
    enum Style {
        case island
        case lockScreen
    }

    let state: WorkoutActivityAttributes.ContentState
    let dictation: LiveActivityDictation
    let style: Style

    var body: some View {
        if state.restEndDate != nil {
            // A timer Text asks for every point an HStack offers, so without a fixed width the
            // bar and the Sets left beside it drew at zero width.
            HStack(spacing: 8) {
                RestCountdownText(state: state)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(state.liveActivityColors.accent)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .leading)

                RestProgressWithContext(state: state, style: progressStyle, context: nextSetText)
            }
        } else {
            SegmentedSets(done: state.setsDone, total: state.setsTotal, colors: state.liveActivityColors)
        }
    }

    /// The rest after a write leads to another Set, so it names that Set's Exercise rather than
    /// count Sets beside the written one.
    private var nextSetText: String? {
        guard dictation.writtenSet != nil else { return nil }
        return "Next: \(state.exerciseName)"
    }

    private var progressStyle: RestProgressWithContext.Style {
        switch style {
        case .island: .island
        case .lockScreen: .lockScreen
        }
    }
}

private struct SaySetLink: View {
    let state: WorkoutActivityAttributes.ContentState
    let diameter: CGFloat

    var body: some View {
        if let url = WorkoutActivityAttributes.dictateURL {
            let colors = state.liveActivityColors

            Link(destination: url) {
                Image(systemName: "mic")
                    .font(.system(size: diameter * 0.45, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: diameter, height: diameter)
                    .background(colors.accent.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Say Set")
        }
    }
}

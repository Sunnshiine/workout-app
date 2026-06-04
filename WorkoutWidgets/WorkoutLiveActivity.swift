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
            PrescribedLoadBadge(state: context.state)
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
        switch state.variant {
        case .setProgress:
            SetProgressBadge(state: state)
        case .nowLifting:
            SetProgressRing(state: state, lineWidth: 4)
                .frame(width: 42, height: 42)
        case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
            PrescriptionStack(state: state)
        }
    }

    @ViewBuilder
    private func expandedCenter(
        for context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
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

    @ViewBuilder
    private func expandedBottom(
        for context: ActivityViewContext<WorkoutActivityAttributes>
    ) -> some View {
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
        case .restTimer:
            RestProgressBar(state: context.state)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .restTimerSetsLeft, .restTimerSetCount:
            RestProgressWithContext(state: context.state, style: .island)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .restTimerClean:
            RestProgressBar(state: context.state)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func compactLeading(for state: WorkoutActivityAttributes.ContentState) -> some View {
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

    @ViewBuilder
    private func compactTrailing(for state: WorkoutActivityAttributes.ContentState) -> some View {
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

    @ViewBuilder
    private func minimalContent(for state: WorkoutActivityAttributes.ContentState) -> some View {
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

private struct LockScreenWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 12) {
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

private struct ExerciseNameStack: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 3) {
            Text(state.exerciseName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.islandPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct WeightForwardStack: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(state.weightValue)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(colors.accent)
                .monospacedDigit()
                .minimumScaleFactor(0.7)

            Text(state.weightUnit)
                .font(.caption.weight(.bold))
                .foregroundStyle(colors.islandSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weight \(state.weightText)")
    }
}

private struct RestCountdownStack: View {
    let state: WorkoutActivityAttributes.ContentState
    var showsLabel = true

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 2) {
            if showsLabel {
                Text("Rest")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(colors.islandSecondaryText)
            }

            RestCountdownText(state: state)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(colors.accent)
                .monospacedDigit()
                .minimumScaleFactor(0.76)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RestCountdownText: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isRestReady {
            Text("Ready")
        } else if let restInterval = state.restInterval {
            Text(timerInterval: restInterval, countsDown: true)
        } else {
            Text("--:--")
        }
    }
}

private struct SetProgressBadge: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        HStack(spacing: 5) {
            Image(systemName: "dumbbell.fill")
            Text(state.setProgressText)
                .monospacedDigit()
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(colors.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(colors.panelFill, in: Capsule())
    }
}

private struct PrescribedLoadBadge: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        Text(state.prescriptionText)
            .font(.caption.weight(.heavy))
            .foregroundStyle(colors.accentText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(colors.accent, in: Capsule())
            .minimumScaleFactor(0.72)
    }
}

private struct SetProgressRing: View {
    let state: WorkoutActivityAttributes.ContentState
    let lineWidth: CGFloat

    var body: some View {
        let colors = state.liveActivityColors

        ZStack {
            Circle()
                .stroke(colors.track, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: state.normalizedProgress)
                .stroke(
                    colors.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("Set progress \(state.setProgressText)")
    }
}

private struct PrescriptionStack: View {
    enum Style {
        case island
        case lockScreen
    }

    let state: WorkoutActivityAttributes.ContentState
    var style: Style = .island

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .trailing, spacing: 2) {
            Text(state.prescribedRepsText)
                .font(.caption.weight(.heavy))
                .foregroundStyle(colors.accent)
                .minimumScaleFactor(0.75)

            Text(state.prescribedLoad)
                .font(.caption2.weight(.bold))
                .foregroundStyle(secondaryTextColor)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prescription \(state.prescriptionText)")
    }

    private var secondaryTextColor: Color {
        switch style {
        case .island:
            state.liveActivityColors.islandSecondaryText
        case .lockScreen:
            state.liveActivityColors.secondaryText
        }
    }
}

private struct RestProgressBar: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        Group {
            if let restInterval = state.restInterval {
                ProgressView(timerInterval: restInterval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .labelsHidden()
                .controlSize(.mini)
                .tint(colors.accent)
                .clipShape(Capsule())
            } else {
                Capsule()
                    .fill(colors.track)
            }
        }
        .frame(height: 5)
        .background(colors.track, in: Capsule())
        .accessibilityLabel("Rest progress")
    }
}

private struct RestProgressWithContext: View {
    enum Style {
        case island
        case lockScreen
    }

    let state: WorkoutActivityAttributes.ContentState
    let style: Style
    var showsBar = true

    var body: some View {
        HStack(spacing: 8) {
            if showsBar {
                RestProgressBar(state: state)
                    .layoutPriority(1)
            }

            if let restContextText = state.restContextText {
                Text(restContextText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch style {
        case .island:
            state.liveActivityColors.islandSecondaryText
        case .lockScreen:
            state.liveActivityColors.secondaryText
        }
    }
}

private struct SegmentedSets: View {
    let done: Int
    let total: Int
    let colors: LiveActivityColors

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<clampedTotal, id: \.self) { index in
                Capsule()
                    .fill(index < clampedDone ? colors.accent : colors.track)
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("Sets \(clampedDone) of \(clampedTotal)")
    }

    private var clampedTotal: Int {
        max(total, 1)
    }

    private var clampedDone: Int {
        min(max(done, 0), clampedTotal)
    }
}

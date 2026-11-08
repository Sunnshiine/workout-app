import SwiftUI

struct ExerciseNameStack: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 3) {
            Text(state.exerciseName)
                .liveActivityFont(.exerciseName)
                .foregroundStyle(colors.islandPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct WeightForwardStack: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(state.weightValue)
                .liveActivityFont(.largeFigure)
                .foregroundStyle(colors.actionInk)
                .minimumScaleFactor(0.7)

            Text(state.weightUnit)
                .liveActivityFont(.label)
                .foregroundStyle(colors.islandSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weight \(state.weightText)")
    }
}

struct RestCountdownStack: View {
    let state: WorkoutActivityAttributes.ContentState
    let showsLabel: Bool
    let digits: LiveActivityType

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 2) {
            if showsLabel {
                Text("Rest")
                    .liveActivityFont(.label)
                    .foregroundStyle(colors.islandSecondaryText)
            }

            // A timer Text takes all the width it is offered, which starves the leading region.
            Text("00:00")
                .hidden()
                .overlay(alignment: .leading) {
                    RestCountdownText(state: state)
                }
                .liveActivityFont(digits)
                .foregroundStyle(colors.islandPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RestCountdownText: View {
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

struct SetProgressBadge: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        HStack(spacing: 5) {
            Image(systemName: "dumbbell.fill")
            Text(state.setProgressText)
        }
        .liveActivityFont(.label)
        .foregroundStyle(colors.actionInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(colors.panelFill, in: Capsule())
    }
}

struct PrescribedLoadBadge: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        Text(state.prescriptionText)
            .liveActivityFont(.label)
            .foregroundStyle(colors.actionText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(colors.actionFill, in: Capsule())
            .minimumScaleFactor(0.72)
    }
}

struct SetProgressRing: View {
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
                    colors.action,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("Set progress \(state.setProgressText)")
    }
}

struct PrescriptionStack: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let colors = state.liveActivityColors

        VStack(alignment: .leading, spacing: 2) {
            Text(state.prescribedRepsText)
                .liveActivityFont(.reference)
                .foregroundStyle(colors.islandPrimaryText)

            Text(state.prescribedLoad)
                .liveActivityFont(.label)
                .foregroundStyle(colors.islandSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prescription \(state.prescriptionText)")
    }
}

/// The fill is rest passing, not progress that happened, so it stays out of the action greens
/// (DESIGN.md, The Green Means Action Rule).
struct RestProgressBar: View {
    let state: WorkoutActivityAttributes.ContentState
    let fill: Color

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
                .tint(fill)
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

/// The rest's bar, then the Exercise it leads to when that is not the one named above, then the
/// queue, which gives up no width to either.
struct RestProgressWithContext: View {
    enum Style {
        case island
        case lockScreen
    }

    let state: WorkoutActivityAttributes.ContentState
    let style: Style
    var context: String?

    var body: some View {
        HStack(spacing: 8) {
            // A long Exercise name beside it must not starve the bar.
            RestProgressBar(state: state, fill: textColor)
                .frame(minWidth: 60)

            if let context {
                Text(context)
                    .liveActivityFont(.label)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }

            PendingWritesLabel(state: state, color: textColor)
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

/// The Set Logs the Sheet does not have yet, in the header's words. It never cuts off, so an unsynced
/// Set never reads as saved.
struct PendingWritesLabel: View {
    let state: WorkoutActivityAttributes.ContentState
    let color: Color

    var body: some View {
        if let queue = state.pendingWritesText {
            Text(queue)
                .liveActivityFont(.label)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)
        }
    }
}

struct SegmentedSets: View {
    let done: Int
    let total: Int
    let colors: LiveActivityColors

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<clampedTotal, id: \.self) { index in
                Capsule()
                    .fill(index < clampedDone ? colors.action : colors.track)
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

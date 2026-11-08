import AppIntents
import SwiftUI

enum LockScreenCardMetrics {
    /// A Lock Screen card draws at 97% of the width it lays out at, so this draws about 44.6pt.
    static let controlSize: CGFloat = 46
    static let controlCornerRadius: CGFloat = 12
}

/// What a card keeps, tried in order until one fits the height the system gives it at the reader's
/// type size, so the room decides what goes and the type itself never stops growing. The spare line
/// goes first: the Cadence and Coach Note, or the second line of a readback's reason. The queue on the
/// offer's spare line then moves up beside the target, which gives way to it. The bottom row keeps
/// the chips' height for as long as it can, because the system can keep a card's last height until
/// the screen wakes, and a readback shorter than the next Set's card would draw its chips cut off.
enum LockScreenCardFit: CaseIterable {
    case whole
    case withoutTheSpareLine
    case withTheBottomRowAtItsOwnHeight

    var keepsTheSpareLine: Bool {
        self == .whole
    }

    var bottomRowHeight: CGFloat? {
        self == .withTheBottomRowAtItsOwnHeight ? nil : LockScreenCardMetrics.controlSize
    }
}

/// Every state of the Lock Screen card in one shape: the Exercise and the rest on the first line, the
/// mic in one place, and a bottom row the height of the chips.
struct LockScreenCardLayout<Lines: View, Mic: View, BottomRow: View>: View {
    private let state: WorkoutActivityAttributes.ContentState
    private let exerciseName: String
    private let lines: (_ keepsTheSpareLine: Bool) -> Lines
    private let mic: Mic
    private let bottomRow: BottomRow

    init(
        state: WorkoutActivityAttributes.ContentState,
        exerciseName: String,
        @ViewBuilder lines: @escaping (_ keepsTheSpareLine: Bool) -> Lines,
        @ViewBuilder mic: () -> Mic,
        @ViewBuilder bottomRow: () -> BottomRow
    ) {
        self.state = state
        self.exerciseName = exerciseName
        self.lines = lines
        self.mic = mic()
        self.bottomRow = bottomRow()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(LockScreenCardFit.allCases, id: \.self) { fit in
                card(fit)
            }
        }
    }

    private func card(_ fit: LockScreenCardFit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // A long name shrinks to fit, and the hidden line keeps the card from losing height to it.
                        ZStack(alignment: .leading) {
                            Text(" ").hidden()

                            Text(exerciseName)
                                .foregroundStyle(state.liveActivityColors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .truncationMode(.middle)
                        }
                        .liveActivityFont(.exerciseName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if state.restEndDate != nil {
                            RestCountdownTrailing(state: state)
                        }
                    }

                    lines(fit.keepsTheSpareLine)
                }

                mic
            }

            bottomRow
                .frame(maxWidth: .infinity, minHeight: fit.bottomRowHeight, alignment: .leading)
        }
        .padding(12)
    }
}

/// The Lock Screen during a rest: the Set the card is on, as the stage shows it, and how to log it.
/// The weight is the one the stage holds, which the card cannot change. The Reps and the RPE are two
/// taps, and the second logs. Anything else is left to the mic or the app.
struct SetOfferLockScreenView: View {
    /// DESIGN.md's Shrink-Then-Truncate Rule: the 13pt target shrinks to 12pt before it cuts off.
    private static let targetFloorScale: CGFloat = 12 / 13

    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        LockScreenCardLayout(state: state, exerciseName: state.exerciseName) { keepsTheSpareLine in
            valuesLine(withTheQueue: !keepsTheSpareLine)

            if keepsTheSpareLine {
                spareLine
            }
        } mic: {
            if let start = state.start {
                LockScreenStartButton(start: start, colors: state.liveActivityColors, diameter: LockScreenCardMetrics.controlSize)
            } else {
                SaySetButton(state: state, diameter: LockScreenCardMetrics.controlSize)
            }
        } bottomRow: {
            howToLog
        }
    }

    @ViewBuilder
    private var howToLog: some View {
        let colors = state.liveActivityColors

        switch state.loggablePress {
        case .ready(let offer):
            LockScreenChipRow(
                offer: offer,
                weight: state.weightText,
                labelColor: colors.primaryText,
                colors: colors,
                spacing: 6,
                chipHeight: LockScreenCardMetrics.controlSize
            )
        case .needsApp:
            // The mic beside it says the other half: this Set can still be said.
            Link(destination: LockScreenChipRow.appURL) {
                Text("Open to log")
                    .liveActivityFont(.control)
                    .foregroundStyle(colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: LockScreenCardMetrics.controlSize)
                    .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                    .contentShape(.rect)
            }
        }
    }

    /// The weight a chip logs, then the coach's target as the Sheet holds it. The target shrinks to the
    /// floor, then cuts off, and gives way to the queue, which no line drops.
    private func valuesLine(withTheQueue: Bool) -> some View {
        let colors = state.liveActivityColors

        // The hidden line keeps a card with no weight as tall as one with it.
        return ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            Text(" ")
                .liveActivityFont(.figure)
                .hidden()

            valuesText(withTheQueue: withTheQueue, colors: colors)
        }
        .liveActivityFont(.reference)
        .foregroundStyle(colors.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func valuesText(withTheQueue: Bool, colors: LiveActivityColors) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !state.weightText.isEmpty {
                SelectedWeightText(state: state, color: colors.primaryText)
                    .liveActivityFont(.figure)
                    .fixedSize()
            }

            Text(state.prescriptionText)
                .lineLimit(1)
                .minimumScaleFactor(Self.targetFloorScale)

            if withTheQueue, let queue = state.pendingWritesText {
                Text("· \(queue)")
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    /// The queue, then the Cadence and Coach Note cut off at the end. A card with neither keeps the
    /// line's height, so the next Set's card holds still.
    private var spareLine: some View {
        HStack(spacing: 0) {
            if let queue = state.pendingWritesText {
                Text(queue)
                    .liveActivityFont(.reference)
                    .lineLimit(1)
                    .fixedSize()
            }

            if let guidance = state.guidance {
                Text(state.pendingWritesText == nil ? guidance : " · \(guidance)")
                    .liveActivityFont(.guidance)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if state.pendingWritesText == nil {
                Text(" ")
                    .liveActivityFont(.guidance)
                    .hidden()
            }
        }
        .foregroundStyle(state.liveActivityColors.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The rest countdown at the end of a line. A timer Text takes all the width it is offered, so a
/// hidden copy of its longest value sets the width.
private struct RestCountdownTrailing: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Text("00:00")
            .hidden()
            .overlay(alignment: .trailing) {
                RestCountdownText(state: state)
                    .multilineTextAlignment(.trailing)
            }
            .liveActivityFont(.figure)
            .foregroundStyle(state.liveActivityColors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
    }
}

/// The weight the stage's card holds, which every chip logs.
struct SelectedWeightText: View {
    let state: WorkoutActivityAttributes.ContentState
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(state.weightText)
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .invalidatableContent()
    }
}

/// Presses Log a Set, which listens without bringing the app forward when it is behind.
struct SaySetButton: View {
    let state: WorkoutActivityAttributes.ContentState
    let diameter: CGFloat

    var body: some View {
        let colors = state.liveActivityColors

        Button(intent: LogSetByVoiceIntent()) {
            Image(systemName: "mic")
                .font(.system(size: diameter * 0.45, weight: .semibold))
                .foregroundStyle(colors.action)
                .frame(width: diameter, height: diameter)
                .background(colors.action.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Say Set")
    }
}

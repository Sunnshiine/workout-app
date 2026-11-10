import AppIntents
import SwiftUI

/// What a readback keeps, tried in order until one fits the card's height at the reader's type size,
/// so the room decides what goes and the type itself never stops growing.
enum LockScreenReadbackFit: CaseIterable {
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

/// A readback's shape on the Lock Screen: the Exercise and the rest on the first line, the mic beside
/// them, and a bottom row.
struct LockScreenReadbackLayout<Lines: View, Mic: View, BottomRow: View>: View {
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
            ForEach(LockScreenReadbackFit.allCases, id: \.self) { fit in
                card(fit)
            }
        }
    }

    private func card(_ fit: LockScreenReadbackFit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The hidden line holds the row's height when a long name shrinks.
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

            Spacer(minLength: 0)

            bottomRow
                .frame(maxWidth: .infinity, minHeight: fit.bottomRowHeight, alignment: .leading)
        }
        .padding(LockScreenCardMetrics.padding)
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

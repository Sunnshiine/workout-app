import AppIntents
import SwiftUI

enum LockScreenCardMetrics {
    /// A Lock Screen card draws at 97% of the width it lays out at, so this draws about 44.6pt.
    static let controlSize: CGFloat = 46
    static let controlCornerRadius: CGFloat = 12
}

/// Every state of the Lock Screen card in one shape: the Exercise and the rest on the first line, the
/// mic in one place, and a bottom row the height of the chips. The system can keep a card's last height
/// until the screen wakes, so a card that grew would draw its chips cut off, and it gives a card
/// 160pt, which every line here fits up to `.xxLarge`. Past it the card keeps all of them at that size
/// over dropping one.
struct LockScreenCardLayout<Lines: View, Mic: View, BottomRow: View>: View {
    private let state: WorkoutActivityAttributes.ContentState
    private let exerciseName: String
    private let lines: Lines
    private let mic: Mic
    private let bottomRow: BottomRow

    init(
        state: WorkoutActivityAttributes.ContentState,
        exerciseName: String,
        @ViewBuilder lines: () -> Lines,
        @ViewBuilder mic: () -> Mic,
        @ViewBuilder bottomRow: () -> BottomRow
    ) {
        self.state = state
        self.exerciseName = exerciseName
        self.lines = lines()
        self.mic = mic()
        self.bottomRow = bottomRow()
    }

    var body: some View {
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

                    lines
                }

                mic
            }

            bottomRow
                .frame(maxWidth: .infinity, minHeight: LockScreenCardMetrics.controlSize, alignment: .leading)
        }
        .padding(12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// The Lock Screen during a rest: the Set the card is on, its Exercise's Last Performed, and how to
/// log it. One tap on an RPE Chip logs a complete pre-fill. Anything else is left to the mic or the
/// app, because a chip must never log a value the athlete has not read.
struct SetOfferLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        LockScreenCardLayout(state: state, exerciseName: state.exerciseName) {
            if state.lastPerformed.isEmpty {
                Text(" ")
                    .liveActivityFont(.lastPerformed)
                    .hidden()
            } else {
                lastPerformedLine
            }

            valuesLine
        } mic: {
            SaySetButton(state: state, diameter: LockScreenCardMetrics.controlSize)
        } bottomRow: {
            howToLog
        }
    }

    @ViewBuilder
    private var howToLog: some View {
        let colors = state.liveActivityColors

        switch state.loggablePress {
        case .ready(let offer):
            RPEChipRow(
                offer: offer,
                labelColor: colors.primaryText,
                colors: colors,
                spacing: 6,
                chipHeight: LockScreenCardMetrics.controlSize
            )
        case .needsApp:
            // The mic beside it says the other half: this Set can still be said.
            Link(destination: RPEChipRow.appURL) {
                Text("Unlock to log")
                    .liveActivityFont(.control)
                    .foregroundStyle(colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: LockScreenCardMetrics.controlSize)
                    .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                    .contentShape(.rect)
            }
        }
    }

    /// What a chip logs sits on the line over the chips, and with no chips the prescription does. The
    /// line drops whole parts, since a count cut off mid-word reads worse than no count. The queue
    /// goes last among them: no other surface says it with the app closed.
    private var valuesLine: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(besideTheValues.enumerated()), id: \.offset) { _, text in
                valuesLine(beside: text)
            }
        }
        .liveActivityFont(.reference)
        .foregroundStyle(state.liveActivityColors.secondaryText)
    }

    private func valuesLine(beside text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // A long cell shrinks to fit, and the hidden line keeps the card from losing height to it.
            ZStack(alignment: .leading) {
                Text(" ").hidden()

                switch state.loggablePress {
                case .ready(let offer):
                    LoggableValuesText(offer: offer, color: state.liveActivityColors.primaryText)
                        .minimumScaleFactor(0.75)
                case .needsApp:
                    Text(state.prescriptionText)
                        .foregroundStyle(state.liveActivityColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .liveActivityFont(.figure)

            if !text.isEmpty {
                Text(text)
                    .lineLimit(1)
            }
        }
    }

    /// Longest first, ending on the values alone.
    private var besideTheValues: [String] {
        let prescription: String? =
            switch state.loggablePress {
            case .ready(let offer): state.prescription(beyond: offer)
            case .needsApp: nil
            }
        let queue = state.pendingWritesText
        let setsLeft = state.restContextText
        return [[prescription, queue, setsLeft], [prescription, queue], [queue, setsLeft], [queue], []]
            .map { $0.compactMap { $0 }.joined(separator: " · ") }
    }

    private var lastPerformedLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                ForEach(state.lastPerformed, id: \.self) { line in
                    // A line shrinks to the floor before it gives up a Set Log.
                    Text(line)
                        .lineLimit(1)
                    Text(line)
                        .liveActivityFont(.lastPerformedFloor)
                        .lineLimit(1)
                }
            }
        }
        .liveActivityFont(.lastPerformed)
        .foregroundStyle(state.liveActivityColors.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last Performed \(state.lastPerformed.first ?? "")")
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

/// What a chip logs, as the stage's Log capsule writes it.
struct LoggableValuesText: View {
    let offer: LoggablePress.Offer
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(offer.valuesText)
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .invalidatableContent()
    }
}

/// One tap logs the Set at that RPE, and the last chip opens the app for an RPE not offered. Nothing
/// is preselected, since the tap is the athlete's report of the Set. The coach's RPE takes the rail's
/// tick and no fill of its own.
struct RPEChipRow: View {
    private enum Metrics {
        static let tickWidth: CGFloat = 18
        static let tickHeight: CGFloat = 3
        static let tickInset: CGFloat = 5
    }

    let offer: LoggablePress.Offer
    let labelColor: Color
    let colors: LiveActivityColors
    let spacing: CGFloat
    let chipHeight: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(offer.rpeChoices, id: \.self) { rpe in
                chip(rpe)
            }
            openApp
        }
    }

    private func chip(_ rpe: String) -> some View {
        Button(intent: LogSetAtRPEIntent(setIdentity: offer.setIdentity, rpe: rpe)) {
            Text(rpe)
                .liveActivityFont(.figure)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .invalidatableContent()
                .frame(maxWidth: .infinity)
                .frame(height: chipHeight)
                .background(colors.action.opacity(0.22), in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                .overlay(alignment: .bottom) {
                    if rpe == offer.prescribedRPE {
                        Capsule()
                            .fill(colors.action)
                            .frame(width: Metrics.tickWidth, height: Metrics.tickHeight)
                            .padding(.bottom, Metrics.tickInset)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(offer.valuesText) at RPE \(rpe)")
        .accessibilityValue(rpe == offer.prescribedRPE ? "Prescribed" : "")
    }

    private var openApp: some View {
        Link(destination: Self.appURL) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(labelColor.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: chipHeight)
                .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                .contentShape(.rect)
        }
        .accessibilityLabel("Another RPE, in the app")
    }

    // Opens the app where it was. No request is attached, so nothing starts listening.
    // swiftlint:disable:next force_unwrapping
    static let appURL = URL(string: "workouttracker://")!
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

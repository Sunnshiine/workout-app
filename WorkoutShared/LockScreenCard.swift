import AppIntents
import SwiftUI

enum LockScreenCardMetrics {
    /// A Lock Screen card draws at 97% of the width it lays out at, so this draws about 44.6pt.
    static let controlSize: CGFloat = 46
    static let controlCornerRadius: CGFloat = 12
    /// DESIGN.md's Shrink-Then-Truncate Rule: the 13pt target shrinks to 12pt before it cuts off.
    static let targetFloorScale: CGFloat = 12 / 13
    static let padding: CGFloat = 16
    /// Draws at about 48pt.
    static let logSize: CGFloat = 50
    static let glyphSize: CGFloat = 20
    /// How far a quiet control's tap target reaches into the card's padding, so its glyph sits on the edge.
    static let controlOverhang: CGFloat = 10

    /// The height the system gives a Lock Screen card at the reader's type size. Every state of the
    /// card fills it, because the system can keep a card's last height until the screen wakes, and
    /// a state shorter than the next would leave that one cut off.
    static func height(at size: DynamicTypeSize) -> CGFloat {
        switch size {
        case ...DynamicTypeSize.large: 160
        case .xLarge: 170
        case .xxLarge: 185
        default: 200
        }
    }
}

/// How a Card Face comes and goes. The system times a Live Activity's transitions, so only the
/// direction is the card's to choose, and under Reduce Motion a face only fades.
enum LockScreenCardMotion {
    /// What the numbers and the Coach Note drift by as one takes the other's place.
    static let swapDrift: CGFloat = 4
    /// What a face travels: up to go forward, down to come back.
    static let turnDrift: CGFloat = 10

    static func drifting(by drift: CGFloat, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: drift).combined(with: .opacity)
    }
}

/// The Lock Screen card during a rest, and while a readback is up over it.
struct LockScreenCard: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let dictation = state.cardReadback {
                if dictation.isAboutASet {
                    DictationLockScreenView(state: state, dictation: dictation)
                } else {
                    NoSetLockScreenView(state: state, dictation: dictation)
                }
            } else {
                face.padding(LockScreenCardMetrics.padding)
            }
        }
        .frame(height: LockScreenCardMetrics.height(at: typeSize))
    }

    /// A face that chooses the Set Log's values needs the offer's choices. The app sends neither
    /// without them, and a card that got one anyway shows its rest.
    @ViewBuilder
    private var face: some View {
        switch (state.face, state.loggablePress) {
        case (.reps, .ready(let offer)):
            LockScreenChoicesFace(state: state, offer: offer, chosenReps: nil)
                .transition(LockScreenCardMotion.drifting(by: LockScreenCardMotion.turnDrift, reduceMotion: reduceMotion))
        case (.rpe(let reps), .ready(let offer)):
            LockScreenChoicesFace(state: state, offer: offer, chosenReps: reps)
                .transition(LockScreenCardMotion.drifting(by: LockScreenCardMotion.turnDrift, reduceMotion: reduceMotion))
        case (.rest, _), (.coachNote, _), (.reps, .needsApp), (.rpe, .needsApp):
            LockScreenRestFace(state: state)
                .transition(LockScreenCardMotion.drifting(by: -LockScreenCardMotion.turnDrift, reduceMotion: reduceMotion))
        }
    }
}

/// The card at rest: the countdown, the Cadence, and the Set's numbers, with one button to log it.
/// The Coach Note opens where the numbers were, and nothing above them moves.
struct LockScreenRestFace: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openNote: String? {
        state.face == .coachNote ? state.coachNote : nil
    }

    var body: some View {
        let colors = state.liveActivityColors

        HStack(alignment: .bottom, spacing: LockScreenCardMetrics.padding) {
            VStack(alignment: .leading, spacing: 0) {
                // No scale factor: the system draws a timer at the smallest scale it is allowed.
                RestCountdownText(state: state)
                    .liveActivityFont(.countdown)
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .contentTransition(.identity)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let cadence = state.cadence {
                    Text(cadence)
                        .liveActivityFont(.caption)
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                        .padding(.top, 2)
                        .accessibilityLabel("Cadence \(cadence)")

                    Spacer(minLength: 8)
                    numbersOrNote
                } else {
                    // With no Cadence the numbers move up under the countdown.
                    numbersOrNote.padding(.top, 16)
                    Spacer(minLength: 0)
                }
            }

            bottomControl
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if openNote == nil {
                quietControls
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var numbersOrNote: some View {
        ZStack(alignment: .bottomLeading) {
            if let note = openNote {
                Text(note)
                    .liveActivityFont(.coachNote)
                    .foregroundStyle(state.liveActivityColors.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .transition(LockScreenCardMotion.drifting(by: LockScreenCardMotion.swapDrift, reduceMotion: reduceMotion))
            } else {
                LockScreenStatsRow(stats: state.stats, colors: state.liveActivityColors)
                    .transition(LockScreenCardMotion.drifting(by: -LockScreenCardMotion.swapDrift, reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Log, which becomes the way back while the Coach Note is open. A Set the card cannot log
    /// opens the app instead.
    @ViewBuilder
    private var bottomControl: some View {
        let colors = state.liveActivityColors

        if openNote != nil {
            Button(intent: TurnLockScreenCardIntent(to: .rest)) {
                LockScreenRoundControl(symbol: "xmark", glyph: colors.primaryText, fill: colors.track)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the Coach Note")
        } else {
            switch state.loggablePress {
            case .ready(let offer):
                Button(intent: TurnLockScreenCardIntent(to: .reps, pressing: offer.setIdentity)) {
                    LockScreenRoundControl(symbol: "checkmark", glyph: colors.actionText, fill: colors.actionFill)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log this Set")
                .accessibilityHint("Then choose the Reps and the RPE")
            case .needsApp:
                Link(destination: LoggablePress.appURL) {
                    LockScreenRoundControl(symbol: "arrow.up.forward", glyph: colors.primaryText, fill: colors.track)
                }
                .accessibilityLabel("Open WorkoutTracker to log this Set")
            }
        }
    }

    /// The mic, or the Start in its place for a Set that opens on a timed effort, then the note
    /// button for an Exercise with a Coach Note.
    private var quietControls: some View {
        let colors = state.liveActivityColors

        return HStack(spacing: 0) {
            if let start = state.start {
                Link(destination: start.url) {
                    LockScreenQuietGlyph(symbol: "timer", color: colors.actionInk)
                }
                .accessibilityLabel("Start the \(start.spokenLabel)")
                .accessibilityHint("Opens WorkoutTracker and counts down 5 seconds")
            } else {
                Button(intent: LogSetByVoiceIntent()) {
                    LockScreenQuietGlyph(symbol: "mic", color: colors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Say Set")
            }

            if state.coachNote != nil {
                Button(intent: TurnLockScreenCardIntent(to: .coachNote)) {
                    LockScreenQuietGlyph(symbol: "text.bubble", color: colors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the Coach Note")
            }
        }
        .padding([.top, .trailing], -LockScreenCardMetrics.controlOverhang)
    }
}

/// The weight, the Reps and the RPE under their units. A row too wide for the card closes its
/// gaps, then sets its values smaller, before any value cuts off.
private struct LockScreenStatsRow: View {
    let stats: [LockScreenCardStat]
    let colors: LiveActivityColors

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(values: .statValue, spacing: 24)
            row(values: .statValue, spacing: 12)
            row(values: .figure, spacing: 12)
        }
    }

    private func row(values: LiveActivityType, spacing: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(stats, id: \.self) { stat in
                VStack(alignment: .leading, spacing: 0) {
                    // A value with no unit keeps the unit's line, so the row's values share a baseline.
                    Text(stat.label.isEmpty ? " " : stat.label)
                        .liveActivityFont(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.secondaryText)

                    Text(stat.value)
                        .liveActivityFont(values)
                        .foregroundStyle(stat.isMissing ? colors.secondaryText : colors.primaryText)
                        .minimumScaleFactor(0.7)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.spoken)
            }
        }
    }
}

/// The card's one filled control, in the bottom corner.
private struct LockScreenRoundControl: View {
    let symbol: String
    let glyph: Color
    let fill: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(glyph)
            .frame(width: LockScreenCardMetrics.logSize, height: LockScreenCardMetrics.logSize)
            .background(fill, in: Circle())
            .contentShape(.circle)
    }
}

/// A bare glyph in a tap target of the card's control size.
struct LockScreenQuietGlyph: View {
    let symbol: String
    let color: Color
    var size = LockScreenCardMetrics.glyphSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: LockScreenCardMetrics.controlSize, height: LockScreenCardMetrics.controlSize)
            .contentShape(.rect)
    }
}

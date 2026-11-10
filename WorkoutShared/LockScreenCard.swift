import AppIntents
import SwiftUI

enum LockScreenCardMetrics {
    /// A Lock Screen card draws at 97% of the size it lays out at, so this draws about 44.6pt.
    static let controlSize: CGFloat = 46
    static let controlCornerRadius: CGFloat = 12
    /// DESIGN.md's Shrink-Then-Truncate Rule: the 13pt target shrinks to 12pt before it cuts off.
    static let targetFloorScale: CGFloat = 12 / 13
    static let padding: CGFloat = 16
    /// Draws at 48.5pt.
    static let logSize: CGFloat = 50
    static let glyphSize: CGFloat = 20
    /// How far a quiet control's tap target reaches into the card's padding, so its glyph sits on the edge.
    static let controlOverhang: CGFloat = 10
    /// Between the countdown's line and the row under it, the Cadence or the numbers.
    static let underCountdown: CGFloat = 8

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

/// How the card moves. A Live Activity runs a transition on the animation of the nearest view
/// that stays put around it, so each of these sits on a container, never on the view that comes or
/// goes.
enum LockScreenCardMotion {
    /// What the numbers and the Coach Note drift by as one takes the other's place.
    static let swapDrift: CGFloat = 4
    /// What a face travels as it arrives: up to go forward, down to come back.
    static let turnDrift: CGFloat = 10

    /// The ink ease (DESIGN.md §7), for a turn and for the Coach Note.
    static let turn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    static let refill = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    /// The flash giving way to the fill. It starts inside the refill's tail and ends inside the
    /// 0.42 s that §7 gives what the athlete sees every Set.
    static let flashFade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28).delay(0.12)
    /// A choosing face leaving for the rest face. Exits are quieter (DESIGN.md §7), so the chips
    /// are gone before the numbers roll.
    static let backToRest = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.1)

    /// Each number starts once the chips have cleared, a beat after the one before it, and the
    /// last ends inside the 0.42 s.
    static func roll(at index: Int) -> Animation {
        turn.delay(0.08 + Double(index) * 0.05)
    }

    static func drifting(by drift: CGFloat, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: drift).combined(with: .opacity)
    }

    /// Only the face that arrives moves. The one that leaves fades, since which way the card
    /// turns next is not known when it is drawn.
    static func arriving(_ turn: LockScreenCardTurn, reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: drifting(by: turn == .forward ? turnDrift : -turnDrift, reduceMotion: reduceMotion),
            removal: .opacity
        )
    }
}

/// The Lock Screen card during a rest, and while a readback is up over it.
struct LockScreenCard: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let dictation = state.cardReadback {
                if dictation.isAboutASet {
                    DictationLockScreenView(state: state, dictation: dictation)
                } else {
                    NoSetLockScreenView(state: state, dictation: dictation)
                }
            } else {
                LockScreenCardFaceView(state: state).padding(LockScreenCardMetrics.padding)
            }
        }
        .frame(height: LockScreenCardMetrics.height(at: typeSize))
    }
}

/// The Card Face the card is on. A choosing face needs the offer's chips.
///
/// The rest face stays drawn, hidden, under a choosing face, so a log changes its numbers in place
/// and they roll to the next Set's.
struct LockScreenCardFaceView: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let choosing = choices

        ZStack {
            LockScreenRestFace(state: state, isShown: choosing == nil)
                .opacity(choosing == nil ? 1 : 0)
                .offset(y: choosing == nil || reduceMotion ? 0 : hiddenRestFaceOffset)
                .accessibilityHidden(choosing != nil)

            if let choosing {
                LockScreenChoicesFace(state: state, offer: choosing.offer, chosenReps: choosing.reps)
                    .transition(LockScreenCardMotion.arriving(state.turn, reduceMotion: reduceMotion))
            }
        }
        .animation(choosing == nil ? LockScreenCardMotion.backToRest : LockScreenCardMotion.turn, value: state.face)
    }

    private var choices: (offer: LoggablePress.Offer, reps: Int?)? {
        switch (state.face, state.loggablePress) {
        case (.reps, .ready(let offer)): (offer, nil)
        case (.rpe(let reps), .ready(let offer)): (offer, reps)
        default: nil
        }
    }

    /// Where the hidden rest face waits, so it arrives the way the card turns: from above as the
    /// Reps go back to it, from below as the RPE logs the Set.
    private var hiddenRestFaceOffset: CGFloat {
        state.face == .reps ? -LockScreenCardMotion.turnDrift : LockScreenCardMotion.turnDrift
    }
}

/// The card at rest: the countdown, the Cadence, and the Set's numbers, with one button to log it.
/// The Coach Note opens where the numbers were, and nothing above them moves.
struct LockScreenRestFace: View {
    let state: WorkoutActivityAttributes.ContentState
    /// False under a choosing face, where the rest face draws no control to press.
    let isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openNote: String? {
        state.face == .coachNote ? state.coachNote : nil
    }

    private var isSettled: Bool {
        state.loggablePress == .settled
    }

    var body: some View {
        let colors = state.liveActivityColors

        HStack(alignment: .bottom, spacing: LockScreenCardMetrics.padding) {
            VStack(alignment: .leading, spacing: 0) {
                if isSettled {
                    Spacer(minLength: 0)
                    numbersOrNote
                } else {
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
                            .padding(.top, LockScreenCardMetrics.underCountdown)
                            .accessibilityLabel("Cadence \(cadence)")

                        Spacer(minLength: 8)
                        numbersOrNote
                    } else {
                        numbersOrNote.padding(.top, LockScreenCardMetrics.underCountdown)
                        Spacer(minLength: 0)
                    }
                }
            }

            if isShown {
                bottomControl
            } else {
                Color.clear.frame(width: LockScreenCardMetrics.logSize)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if openNote == nil, !isSettled, isShown {
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
                LockScreenStatsRow(stats: state.stats, colors: state.liveActivityColors, reduceMotion: reduceMotion)
                    .transition(LockScreenCardMotion.drifting(by: -LockScreenCardMotion.swapDrift, reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bottomControl: some View {
        let colors = state.liveActivityColors

        if openNote != nil {
            Button(intent: TurnLockScreenCardIntent(to: .rest, pressing: nil)) {
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
            case .settled:
                EmptyView()
            }
        }
    }

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
                Button(intent: TurnLockScreenCardIntent(to: .coachNote, pressing: nil)) {
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
    let reduceMotion: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(values: .statValue, spacing: 24)
            row(values: .statValue, spacing: 12)
            row(values: .figure, spacing: 12)
        }
    }

    private func row(values: LiveActivityType, spacing: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                VStack(alignment: .leading, spacing: 0) {
                    Text(stat.label)
                        .liveActivityFont(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.secondaryText)

                    Text(stat.value)
                        .liveActivityFont(values)
                        .foregroundStyle(stat.isMissing ? colors.secondaryText : colors.primaryText)
                        .minimumScaleFactor(0.7)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(LockScreenCardMotion.roll(at: index), value: stat.value)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.spoken)
            }
        }
    }
}

/// The card's one filled control.
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

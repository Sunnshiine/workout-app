import AppIntents
import SwiftUI

/// The card while the athlete chooses a Set Log's values: the Reps, then the RPE for the Reps
/// tapped. A Reps tap turns the card and writes nothing, so a Set half chosen never logs, and the
/// RPE tap logs. Nothing is preselected, since each tap is the athlete's report of the Set, and the
/// coach's values take a tick.
struct LockScreenChoicesFace: View {
    private enum Metrics {
        static let chipCornerRadius: CGFloat = 16
        static let chipSpacing: CGFloat = 6
        static let tickWidth: CGFloat = 18
        static let tickHeight: CGFloat = 3
        static let tickInset: CGFloat = 10
        static let backGlyphSize: CGFloat = 18
        /// The back control's tap target reaches into the padding, so its chevron sits on the edge.
        static let backOverhang: CGFloat = 12
        static let headerOverhang: CGFloat = 6
    }

    let state: WorkoutActivityAttributes.ContentState
    let offer: LoggablePress.Offer
    /// The Reps the athlete tapped. Nil while the card offers the Reps.
    let chosenReps: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            header
                .padding(.top, -Metrics.headerOverhang)
                .padding(.leading, -Metrics.backOverhang)

            ZStack {
                if let chosenReps {
                    rpeChips(for: chosenReps)
                        .transition(LockScreenCardMotion.drifting(by: LockScreenCardMotion.turnDrift, reduceMotion: reduceMotion))
                } else {
                    repsChips
                        .transition(LockScreenCardMotion.drifting(by: -LockScreenCardMotion.turnDrift, reduceMotion: reduceMotion))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        let colors = state.liveActivityColors

        return HStack(spacing: 2) {
            Button(intent: back) {
                LockScreenQuietGlyph(symbol: "chevron.backward", color: colors.secondaryText, size: Metrics.backGlyphSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chosenReps == nil ? "Back" : "Back to the Reps")

            Text(chosenReps == nil ? "Reps" : "RPE")
                .liveActivityFont(.figure)
                .foregroundStyle(colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Text(chosenSoFar)
                .liveActivityFont(.pill)
                .foregroundStyle(colors.secondaryText)
                .minimumScaleFactor(0.8)
        }
        .lineLimit(1)
    }

    private var back: TurnLockScreenCardIntent {
        guard chosenReps != nil else { return TurnLockScreenCardIntent(to: .rest, pressing: nil) }
        return TurnLockScreenCardIntent(to: .reps, pressing: offer.setIdentity)
    }

    /// `267.5 lbs`, then `267.5 lbs · 3 reps` once the Reps are tapped.
    private var chosenSoFar: String {
        let reps = chosenReps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
        return [state.weightOnTheCard, reps].compactMap { $0 }.joined(separator: " · ")
    }

    private var repsChips: some View {
        HStack(spacing: Metrics.chipSpacing) {
            ForEach(offer.repChoices, id: \.self) { reps in
                chip("\(reps)", ticked: offer.prescribedReps.contains(reps)) {
                    TurnLockScreenCardIntent(to: .rpe(reps: reps), pressing: offer.setIdentity)
                }
                .accessibilityLabel(reps == 1 ? "1 rep" : "\(reps) reps")
                .accessibilityHint("Then choose the RPE")
            }
        }
    }

    private func rpeChips(for reps: Int) -> some View {
        HStack(spacing: Metrics.chipSpacing) {
            ForEach(offer.rpeChoices, id: \.self) { rpe in
                chip(rpe, ticked: rpe == offer.prescribedRPE) {
                    LogSetAtRPEIntent(setIdentity: offer.setIdentity, reps: reps, rpe: rpe)
                }
                .accessibilityLabel("Log \(state.weightText) for \(reps) at RPE \(rpe)")
            }
        }
    }

    private func chip<Intent: AppIntent>(_ label: String, ticked: Bool, intent: () -> Intent) -> some View {
        let colors = state.liveActivityColors

        return Button(intent: intent()) {
            Text(label)
                .liveActivityFont(.largeFigure)
                .foregroundStyle(colors.actionText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .invalidatableContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colors.actionFill, in: .rect(cornerRadius: Metrics.chipCornerRadius))
                .overlay(alignment: .bottom) {
                    if ticked {
                        Capsule()
                            .fill(colors.actionText)
                            .frame(width: Metrics.tickWidth, height: Metrics.tickHeight)
                            .padding(.bottom, Metrics.tickInset)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(ticked ? "Prescribed" : "")
    }
}

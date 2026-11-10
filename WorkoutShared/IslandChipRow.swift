import AppIntents
import SwiftUI

/// The island's bottom row while it offers a Set: Reps Chips, then RPE Chips for the Reps tapped. A
/// Reps tap turns the row and writes nothing, so a Set half chosen never logs, and the RPE tap logs.
/// Nothing is preselected, since each tap is the athlete's report of the Set. Each chip is an
/// `actionFill` under `actionText`, as the Log capsule is, and the coach's values take a tick of
/// that cream, since an `action` mark vanishes on the Day fill. Each chip carries the Set Log's own mark, `×5`
/// for Reps and `@7` for an RPE, so the two rows never read as one.
struct IslandChipRow: View {
    private enum Metrics {
        static let tickWidth: CGFloat = 18
        static let tickHeight: CGFloat = 3
        static let tickInset: CGFloat = 5
    }

    let offer: LoggablePress.Offer
    /// The card's face, since the island has none of its own: RPE Chips on the RPE face, Reps Chips on any other.
    let face: LockScreenCardFace
    /// The weight the RPE tap logs, as VoiceOver reads it.
    let weight: String
    let labelColor: Color
    let colors: LiveActivityColors
    let spacing: CGFloat
    let chipHeight: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            if case .rpe(let reps) = face {
                back(from: reps)
                ForEach(offer.rpeChoices, id: \.self) { rpe in
                    chip("@\(rpe)", ticked: rpe == offer.prescribedRPE) {
                        LogSetAtRPEIntent(setIdentity: offer.setIdentity, reps: reps, rpe: rpe)
                    }
                    .accessibilityLabel("Log \(weight) for \(reps) at RPE \(rpe)")
                }
            } else {
                ForEach(offer.repChoices, id: \.self) { reps in
                    chip("×\(reps)", ticked: offer.prescribedReps.contains(reps)) {
                        TurnLockScreenCardIntent(to: .rpe(reps: reps), pressing: offer.setIdentity)
                    }
                    .accessibilityLabel(reps == 1 ? "1 rep" : "\(reps) reps")
                    .accessibilityHint("Then choose the RPE")
                }
                openApp
            }
        }
    }

    private func chip<Intent: AppIntent>(_ label: String, ticked: Bool, intent: () -> Intent) -> some View {
        Button(intent: intent()) {
            Text(label)
                .liveActivityFont(.figure)
                .foregroundStyle(colors.actionText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .invalidatableContent()
                .frame(maxWidth: .infinity)
                .frame(height: chipHeight)
                .background(colors.actionFill, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
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

    /// The Reps already tapped, which a tap turns back into Reps Chips.
    private func back(from reps: Int) -> some View {
        Button(intent: TurnLockScreenCardIntent(to: .rest, pressing: nil)) {
            HStack(spacing: 1) {
                Image(systemName: "chevron.backward")
                    .font(.caption.weight(.bold))
                Text("×\(reps)")
                    .liveActivityFont(.figure)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(labelColor)
            .invalidatableContent()
            .frame(maxWidth: .infinity)
            .frame(height: chipHeight)
            .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reps == 1 ? "1 rep" : "\(reps) reps")
        .accessibilityHint("Choose the Reps again")
    }

    private var openApp: some View {
        Link(destination: LoggablePress.appURL) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(labelColor.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: chipHeight)
                .background(colors.track, in: .rect(cornerRadius: LockScreenCardMetrics.controlCornerRadius))
                .contentShape(.rect)
        }
        .accessibilityLabel("Other Reps, in the app")
    }
}

/// The Start in the mic's place, for a Set whose Exercise opens on a timed effort. It opens the app
/// on the Set's card, which counts the effort as a tap on its own control does.
struct LockScreenStartButton: View {
    let start: LockScreenStartOffer
    let colors: LiveActivityColors
    let diameter: CGFloat

    var body: some View {
        Link(destination: start.url) {
            Image(systemName: "timer")
                .font(.system(size: diameter * 0.45, weight: .semibold))
                .foregroundStyle(colors.actionText)
                .frame(width: diameter, height: diameter)
                .background(colors.actionFill, in: Circle())
        }
        .accessibilityLabel("Start the \(start.spokenLabel)")
        .accessibilityHint("Opens WorkoutTracker and counts down 5 seconds")
    }
}

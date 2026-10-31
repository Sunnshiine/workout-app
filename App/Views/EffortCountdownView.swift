import SwiftUI

/// The card's timed effort, present only on a Pending Set it logs whose Exercise has one.
struct SetCardTimedEffort {
    let countdown: SetCardCountdown
    let start: () -> Void
    let cancel: () -> Void
}

/// The control in the card's head that names the timed effort, `10 s hold` or `40 s`. One tap
/// starts the Lead-in; a tap while it runs stops it.
struct TimedEffortControl: View {
    let timedEffort: SetCardTimedEffort
    let targetHeight: CGFloat
    @Environment(\.themePalette) private var palette

    private var isRunning: Bool { timedEffort.countdown.run != nil }
    private var effort: TimedEffort { timedEffort.countdown.effort }

    var body: some View {
        Button(action: isRunning ? timedEffort.cancel : timedEffort.start) {
            Label {
                Text(effort.controlLabel)
            } icon: {
                // Only the glyph turns green while it runs: green text on the pill reads dim in Night.
                Image(systemName: "timer")
                    .foregroundStyle(isRunning ? palette.action : palette.textPrimary)
            }
            .font(Theme.font(.queuePill))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.pillFill, in: .capsule)
            .overlay(Capsule().strokeBorder(palette.pillStroke, lineWidth: 1))
            .frame(minHeight: targetHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effort.spokenLabel)
        .accessibilityHint(isRunning ? "Stops the countdown" : "Counts down 5 seconds, then the \(effort.spokenLabel)")
        .accessibilityIdentifier("timed-effort-button")
    }
}

/// The running Effort Countdown, drawn over the card's values in their frame (DESIGN.md §5.2):
/// a numeral to read at arm's length, what it counts, and a bar that steps once a second. The
/// voice and the taps carry it for an athlete not looking. A tap anywhere on it stops it.
struct EffortCountdownView: View {
    let run: CountdownRun
    let onCancel: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: run.start, by: 1)) { context in
            let face = EffortCountdownFace(run, at: context.date)
            VStack(spacing: 10) {
                Text(face.caption)
                    .font(Theme.font(.heading))
                    .foregroundStyle(palette.textSecondary)
                Text(face.numeral)
                    .font(Theme.font(.countdownNumeral))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                progressBar(face.progress)
                Text(face.hint)
                    .font(Theme.font(.fieldLabel))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.surface)
            .contentShape(.rect)
            .onTapGesture(perform: onCancel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(run.effort.spokenLabel) countdown")
            .accessibilityValue(face.accessibilityValue)
            .accessibilityHint("Ends the countdown")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onCancel() }
            .accessibilityIdentifier("effort-countdown")
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        Capsule()
            .fill(palette.railFill)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(palette.action)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .padding(.horizontal, 32)
            .accessibilityHidden(true)
    }
}

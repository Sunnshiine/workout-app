import SwiftUI

struct RestPillView: View {
    let restTimer: RestTimer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let remaining = restTimer.remaining(at: context.date)
            if remaining > 0 {
                pill(remaining: remaining)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(transition)
            }
        }
    }

    private func pill(remaining: TimeInterval) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Text("Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(formatted(remaining))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(countdownColor(for: remaining))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)

                Button(action: restTimer.dismiss) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss rest")
                .accessibilityIdentifier("rest-pill-dismiss")
            }

            hairline(remaining: remaining)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(palette.pillFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(palette.pillStroke, lineWidth: 1)
        }
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(for: remaining))
        .accessibilityIdentifier("rest-pill")
    }

    private func hairline(remaining: TimeInterval) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(countdownColor(for: remaining))
                .frame(width: proxy.size.width * progressFraction(for: remaining), height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 3)
    }

    private var transition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            .opacity
                .combined(with: .scale(scale: 0.92, anchor: .bottom))
                .combined(with: .offset(y: 16))
        }
    }

    private func countdownColor(for remaining: TimeInterval) -> Color {
        remaining <= 5 ? palette.accent : palette.valueText
    }

    private func progressFraction(for remaining: TimeInterval) -> CGFloat {
        guard restTimer.duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, remaining / restTimer.duration)))
    }

    private func formatted(_ remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(remaining)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func accessibilityLabel(for remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(remaining)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0, seconds > 0 {
            return "Rest, \(minutes) minutes \(seconds) seconds remaining"
        }
        if minutes > 0 {
            return "Rest, \(minutes) minutes remaining"
        }
        return "Rest, \(seconds) seconds remaining"
    }
}

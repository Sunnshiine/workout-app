import SwiftUI

struct RestPillView: View {
    let restTimer: RestTimer
    private let visualBaselineDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @State private var hapticPlayer = RestHapticPlayer()
    @State private var lastHapticElapsed: TimeInterval?
    @State private var playedHapticEvents: Set<RestHapticEvent> = []
    @State private var finalFivePulse = false
    @State private var restartPulse = false

    init(restTimer: RestTimer, visualBaselineDate: Date? = nil) {
        self.restTimer = restTimer
        self.visualBaselineDate = visualBaselineDate
    }

    var body: some View {
        if let visualBaselineDate {
            pillContainer(at: visualBaselineDate)
        } else {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let remaining = restTimer.remaining(at: context.date)
                pillContainer(at: context.date)
                    .task(id: restTimer.restartRevision) {
                        resetHapticProgress()
                        await playRestartBeat(for: restTimer.restartRevision)
                    }
                    .task(id: hapticTickID(for: context.date)) {
                        await fireDueHaptics(at: context.date)
                    }
                    .task(id: finalFivePulseID(for: remaining)) {
                        await playFinalFivePulse(for: remaining)
                    }
            }
        }
    }

    private func pillContainer(at date: Date) -> some View {
        let remaining = restTimer.remaining(at: date)

        return ZStack {
            if restTimer.deadline != nil {
                pill(remaining: remaining)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(transition)
                    .scaleEffect(restartPulseScale)
                    .brightness(restartPulseBrightness)
                    .opacity(restartPulseOpacity)
                    .animation(restartAnimation, value: restartPulse)
            }
        }
    }

    private func pill(remaining: TimeInterval) -> some View {
        let cue = RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion)

        return VStack(spacing: 6) {
            HStack(spacing: 14) {
                Text(restTimer.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(formatted(remaining))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(countdownColor(for: cue))
                    .opacity(countdownOpacity(for: cue))
                    .scaleEffect(finalFiveScale(for: cue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .animation(finalFiveAnimation(for: cue), value: finalFivePulse)
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

            hairline(remaining: remaining, cue: cue)
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

    private func hairline(remaining: TimeInterval, cue: RestPillUrgencyCue) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(countdownColor(for: cue).opacity(countdownOpacity(for: cue)))
                .frame(width: proxy.size.width * progressFraction(for: remaining), height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: 1, y: finalFiveScale(for: cue), anchor: .center)
                .animation(finalFiveAnimation(for: cue), value: finalFivePulse)
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

    private var restartPulseScale: CGFloat {
        guard !reduceMotion, restartPulse else { return 1 }
        return 1.025
    }

    private var restartPulseBrightness: Double {
        guard !reduceMotion, restartPulse else { return 0 }
        return 0.035
    }

    private var restartPulseOpacity: Double {
        guard reduceMotion, restartPulse else { return 1 }
        return 0.82
    }

    private var restartAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.18)
    }

    private func playRestartBeat(for revision: Int) async {
        guard revision > 1 else { return }
        restartPulse = true
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        restartPulse = false
    }

    private func playFinalFivePulse(for remaining: TimeInterval) async {
        let cue = RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion)
        guard cue.shouldBreathe else {
            finalFivePulse = false
            return
        }

        finalFivePulse = true
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        finalFivePulse = false
    }

    private func fireDueHaptics(at now: Date) async {
        guard restTimer.deadline != nil else { return }

        let elapsed = elapsedRestTime(at: now)
        if scenePhase != .active {
            lastHapticElapsed = elapsed
            if elapsed >= restTimer.duration {
                restTimer.dismiss()
            }
            return
        }

        guard let previousElapsed = lastHapticElapsed else {
            lastHapticElapsed = elapsed
            if elapsed >= restTimer.duration {
                restTimer.dismiss()
            }
            return
        }

        let events = RestHapticSchedule(duration: restTimer.duration).events
            .filter { event in
                event.offset > previousElapsed && event.offset <= elapsed && !playedHapticEvents.contains(event)
            }

        for event in events {
            playedHapticEvents.insert(event)
            hapticPlayer.play(event.kind)
            if event.kind == .expiryBuzz {
                await dismissAfterExpiryBeat()
            }
        }

        lastHapticElapsed = elapsed
        let expiryEvent = RestHapticEvent(offset: restTimer.duration, kind: .expiryBuzz)
        if elapsed >= restTimer.duration && !playedHapticEvents.contains(expiryEvent) {
            restTimer.dismiss()
        }
    }

    private func dismissAfterExpiryBeat() async {
        let deadline = restTimer.deadline
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, restTimer.deadline == deadline else { return }
        restTimer.dismiss()
    }

    private func resetHapticProgress() {
        lastHapticElapsed = nil
        playedHapticEvents = []
        finalFivePulse = false
    }

    private func elapsedRestTime(at now: Date) -> TimeInterval {
        guard restTimer.deadline != nil else { return 0 }
        let remaining = restTimer.remaining(at: now)
        return max(0, restTimer.duration - remaining)
    }

    private func hapticTickID(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private func finalFivePulseID(for remaining: TimeInterval) -> Int {
        RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion).remainingSeconds
    }

    private func countdownColor(for cue: RestPillUrgencyCue) -> Color {
        cue.isActive ? palette.accent : palette.valueText
    }

    private func countdownOpacity(for cue: RestPillUrgencyCue) -> Double {
        cue.isActive ? cue.accentIntensity : 1
    }

    private func finalFiveScale(for cue: RestPillUrgencyCue) -> CGFloat {
        finalFivePulse ? CGFloat(cue.breathScale) : 1
    }

    private func finalFiveAnimation(for cue: RestPillUrgencyCue) -> Animation? {
        cue.shouldBreathe ? .smooth(duration: 0.22) : nil
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
            return "\(restTimer.label), \(minutes) minutes \(seconds) seconds remaining"
        }
        if minutes > 0 {
            return "\(restTimer.label), \(minutes) minutes remaining"
        }
        return "\(restTimer.label), \(seconds) seconds remaining"
    }
}

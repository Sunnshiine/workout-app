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
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
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
        let presentation = RestPillPresentation(
            kind: restTimer.kind,
            remaining: remaining,
            duration: restTimer.duration
        )

        return ZStack {
            if restTimer.deadline != nil {
                pill(remaining: remaining, presentation: presentation)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * 0.5
                    }
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

    private func pill(remaining: TimeInterval, presentation: RestPillPresentation) -> some View {
        let cue = RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion)

        return VStack(spacing: 6) {
            Text(presentation.countdownText)
                .font(.system(size: 27, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(countdownColor(for: cue))
                .opacity(countdownOpacity(for: cue))
                .scaleEffect(finalFiveScale(for: cue))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .animation(finalFiveAnimation(for: cue), value: finalFivePulse)
                .accessibilityHidden(true)

            hairline(presentation: presentation, cue: cue)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .overlay {
            Capsule()
                .stroke(palette.pillStroke.opacity(0.54), lineWidth: 1)
        }
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("rest-pill")
    }

    private func hairline(presentation: RestPillPresentation, cue: RestPillUrgencyCue) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack.opacity(0.46))
                Capsule()
                    .fill(railColor(for: cue).opacity(countdownOpacity(for: cue)))
                    .frame(width: proxy.size.width * CGFloat(presentation.progressFraction))
                    .scaleEffect(x: 1, y: finalFiveScale(for: cue), anchor: .center)
                    .animation(.linear(duration: 1.0 / 30), value: presentation.progressFraction)
                    .animation(finalFiveAnimation(for: cue), value: finalFivePulse)
            }
        }
        .frame(height: 4)
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
                restTimer.expireIfNeeded(at: now)
            }
            return
        }

        guard let previousElapsed = lastHapticElapsed else {
            lastHapticElapsed = elapsed
            if elapsed >= restTimer.duration {
                restTimer.expireIfNeeded(at: now)
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
            restTimer.expireIfNeeded(at: now)
        }
    }

    private func dismissAfterExpiryBeat() async {
        let deadline = restTimer.deadline
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, restTimer.deadline == deadline else { return }
        restTimer.expireIfNeeded(at: Date())
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

    private func railColor(for cue: RestPillUrgencyCue) -> Color {
        cue.isActive ? palette.accent : palette.pillStroke
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

}

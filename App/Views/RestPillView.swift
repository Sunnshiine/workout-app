import SwiftUI

struct RestPillView: View {
    let restTimer: RestTimer
    private let visualBaselineDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @State private var finalFivePulse = false
    @State private var restartPulse = false
    @State private var lastInterval: RestInterval?

    init(restTimer: RestTimer, visualBaselineDate: Date? = nil) {
        self.restTimer = restTimer
        self.visualBaselineDate = visualBaselineDate
    }

    var body: some View {
        if let visualBaselineDate {
            pillContainer(at: visualBaselineDate)
        } else {
            TimelineView(.periodic(from: shownInterval?.start ?? .now, by: 1)) { context in
                let remaining = restTimer.remaining(at: context.date)
                pillContainer(at: context.date)
                    .task(id: restTimer.restartRevision) {
                        finalFivePulse = false
                        await playRestartBeat(for: restTimer.restartRevision)
                    }
                    .task(id: hapticTickID(for: context.date)) {
                        fireDueHaptics(at: context.date)
                    }
                    .task(id: finalFivePulseID(for: remaining)) {
                        await playFinalFivePulse(for: remaining)
                    }
                    .onChange(of: restTimer.expiryHaptics) { _, events in
                        playExpiryHaptics(events)
                    }
            }
            .id(shownInterval?.start)
            // A restart swaps this identity inside the log's animation. Without the opaque capsule,
            // a cross-fade would draw both countdowns at once, so the swap is instant.
            .transition(.identity)
            .onChange(of: restTimer.interval, initial: true) { _, interval in
                if let interval { lastInterval = interval }
            }
        }
    }

    /// The live interval, or the last one once it clears. The stage fades this view out after rest
    /// ends, and without the last interval the fade would draw an empty body.
    private var shownInterval: RestInterval? {
        restTimer.interval ?? lastInterval
    }

    private func pillContainer(at date: Date) -> some View {
        let interval = shownInterval
        let remaining = interval?.remaining(at: date) ?? 0
        let presentation = RestPillPresentation(
            kind: interval?.kind ?? .standard,
            remaining: remaining,
            duration: interval?.duration ?? 0
        )

        return ZStack {
            if interval != nil {
                pill(remaining: remaining, presentation: presentation)
                    .padding(.horizontal)
                    .scaleEffect(restartPulseScale)
                    .brightness(restartPulseBrightness)
                    .opacity(restartPulseOpacity)
                    .animation(restartAnimation, value: restartPulse)
            }
        }
    }

    private func pill(remaining: TimeInterval, presentation: RestPillPresentation) -> some View {
        let cue = RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion)

        return HStack(spacing: 8) {
            ring(presentation: presentation, cue: cue)

            Text(presentation.countdownText)
                .font(Theme.font(.statsValue))
                .foregroundStyle(countdownColor(for: cue))
                .opacity(countdownOpacity(for: cue))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .scaleEffect(finalFiveScale(for: cue), anchor: .leading)
        .animation(finalFiveAnimation(for: cue), value: finalFivePulse)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("rest-pill")
    }

    private func ring(presentation: RestPillPresentation, cue: RestPillUrgencyCue) -> some View {
        ZStack {
            Circle()
                .strokeBorder(palette.progressTrack.opacity(0.55), lineWidth: 3)
            Circle()
                .inset(by: 1.5)
                .trim(from: 0, to: CGFloat(presentation.progressFraction))
                .stroke(
                    arcColor(for: cue).opacity(countdownOpacity(for: cue)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
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

    /// Pure playback: the module decides which taps are due on this tick; the pill only forwards
    /// them to the haptic engine, so it no longer owns the schedule or the elapsed/played
    /// bookkeeping.
    private func fireDueHaptics(at now: Date) {
        for event in restTimer.dueHapticEvents(at: now, sceneActive: scenePhase == .active) {
            HapticPlayer.shared.play(.rest(event.kind))
        }
    }

    /// Plays the expiry buzz the module authored at the deadline. The module holds the interval a
    /// beat so the pill is still on screen to feel it; the pill only decides whether the scene is
    /// active, mirroring the tap suppression rule.
    private func playExpiryHaptics(_ events: [RestHapticEvent]) {
        guard scenePhase == .active else { return }
        for event in events {
            HapticPlayer.shared.play(.rest(event.kind))
        }
    }

    private func hapticTickID(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private func finalFivePulseID(for remaining: TimeInterval) -> Int {
        RestPillUrgencyCue(remaining: remaining, reduceMotion: reduceMotion).remainingSeconds
    }

    private func countdownColor(for cue: RestPillUrgencyCue) -> Color {
        cue.isActive ? palette.actionInk : palette.valueText
    }

    private func arcColor(for cue: RestPillUrgencyCue) -> Color {
        cue.isActive ? palette.actionInk : palette.accent
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

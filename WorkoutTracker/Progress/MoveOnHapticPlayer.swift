import Foundation

#if canImport(CoreHaptics)
    import CoreHaptics
#endif

/// The Move On ceremony's **one** Crisp Core Haptics pattern (DESIGN.md §7): a
/// single swell-and-peak timed to the choreography — a continuous intensity swell
/// rising through the stem's climb (1.0s), then a sharp peak transient as the bird
/// drops to the branch tip (≈1.1s). There is one identical pattern for every Move
/// On; the old `UINotificationFeedbackGenerator` / `UIImpactFeedbackGenerator`
/// fake (and its perfect-Session variant) is retired.
@MainActor
final class MoveOnHapticPlayer {
    #if canImport(CoreHaptics)
        private var engine: CHHapticEngine?

        func play() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

            do {
                let engine = try activeEngine()
                let player = try engine.makePlayer(with: try Self.pattern())
                try player.start(atTime: 0)
            } catch {
                engine = nil
            }
        }

        private func activeEngine() throws -> CHHapticEngine {
            if let engine { return engine }

            let engine = try CHHapticEngine()
            try engine.start()
            self.engine = engine
            return engine
        }

        private static func pattern() throws -> CHHapticPattern {
            let swell = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
                ],
                relativeTime: 0,
                duration: Theme.Motion.ceremonyStem
            )

            // The swell rises through the stem's climb, then the peak transient lands
            // with the bird — the Crisp log tuning (1.0 / 0.65).
            let swellCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.2),
                    CHHapticParameterCurve.ControlPoint(relativeTime: Theme.Motion.ceremonyStem, value: 1.0)
                ],
                relativeTime: 0
            )

            let peak = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(Theme.Haptics.logTap.intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(Theme.Haptics.logTap.sharpness))
                ],
                relativeTime: Theme.Motion.ceremonyStem + Theme.Motion.ceremonyBeat
            )

            return try CHHapticPattern(events: [swell, peak], parameterCurves: [swellCurve])
        }
    #else
        func play() {}
    #endif
}

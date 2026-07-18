import UIKit

#if canImport(CoreHaptics)
    import CoreHaptics
#endif

/// Plays the four-word semantic vocabulary (#421) with per-variant tunings:
/// RPE detent tick, Log firm tap, Skip soft dud, and the one Move On pattern
/// timed to the selected ceremony pacing. CoreHaptics with a UIKit-generator
/// fallback when the engine is unavailable.
@MainActor
final class MotionLabHaptics {
    func tick(_ tuning: MotionLabHapticTuning) {
        transient(tuning.tick)
    }

    func logTap(_ tuning: MotionLabHapticTuning) {
        transient(tuning.log)
    }

    func skipDud(_ tuning: MotionLabHapticTuning) {
        transient(tuning.skip)
    }

    func moveOn(_ tuning: MotionLabHapticTuning, ceremony: MotionLabCeremonyVariant) {
        #if canImport(CoreHaptics)
            do {
                try play(pattern: moveOnPattern(tuning.moveOnShape, ceremony: ceremony))
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        #else
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    #if canImport(CoreHaptics)
        private var engine: CHHapticEngine?

        private struct HapticsUnavailable: Error {}

        private func transient(_ t: MotionLabHapticTuning.Transient) {
            do {
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: t.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: t.sharpness)
                    ],
                    relativeTime: 0
                )
                try play(pattern: CHHapticPattern(events: [event], parameters: []))
            } catch {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: CGFloat(t.intensity))
            }
        }

        private func play(pattern: CHHapticPattern) throws {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { throw HapticsUnavailable() }
            do {
                let engine = try activeEngine()
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
            } catch {
                engine = nil
                throw error
            }
        }

        private func activeEngine() throws -> CHHapticEngine {
            if let engine { return engine }

            let engine = try CHHapticEngine()
            try engine.start()
            self.engine = engine
            return engine
        }

        private func moveOnPattern(
            _ shape: MotionLabHapticTuning.MoveOnShape,
            ceremony: MotionLabCeremonyVariant
        ) throws -> CHHapticPattern {
            let landing = ceremony.birdStart + ceremony.birdDuration * 0.7
            switch shape {
            case .swellAndPeak:
                let swell = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
                    ],
                    relativeTime: 0,
                    duration: ceremony.stemDuration
                )
                let peak = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.80),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.50)
                    ],
                    relativeTime: landing
                )
                let echo = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.30),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
                    ],
                    relativeTime: landing + 0.12
                )
                let rise = CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.25),
                        CHHapticParameterCurve.ControlPoint(relativeTime: ceremony.stemDuration, value: 1.0)
                    ],
                    relativeTime: 0
                )
                return try CHHapticPattern(events: [swell, peak, echo], parameterCurves: [rise])
            case .warmSwell:
                let swell = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                    ],
                    relativeTime: 0,
                    duration: ceremony.total
                )
                let land = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.50),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                    ],
                    relativeTime: landing
                )
                let arc = CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.2),
                        CHHapticParameterCurve.ControlPoint(relativeTime: landing, value: 1.0),
                        CHHapticParameterCurve.ControlPoint(relativeTime: ceremony.total, value: 0.35)
                    ],
                    relativeTime: 0
                )
                return try CHHapticPattern(events: [swell, land], parameterCurves: [arc])
            case .risingTriplet:
                let steps = [0.33, 0.66, 1.0].enumerated().map { index, fraction in
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.30 + 0.20 * Float(index)),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.40)
                        ],
                        relativeTime: ceremony.stemDuration * fraction
                    )
                }
                let bloom = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.50),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.20)
                    ],
                    relativeTime: ceremony.birdStart,
                    duration: max(ceremony.birdDuration, 0.3)
                )
                let fade = CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: ceremony.birdStart, value: 1.0),
                        CHHapticParameterCurve.ControlPoint(relativeTime: ceremony.total + 0.2, value: 0.0)
                    ],
                    relativeTime: 0
                )
                return try CHHapticPattern(events: steps + [bloom], parameterCurves: [fade])
            }
        }
    #else
        private func transient(_ t: MotionLabHapticTuning.Transient) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: CGFloat(t.intensity))
        }
    #endif
}

import Foundation

#if canImport(CoreHaptics)
    import CoreHaptics
#endif

@MainActor
final class RestHapticPlayer {
    #if canImport(CoreHaptics)
        private var engine: CHHapticEngine?

        func play(_ kind: RestHapticKind) {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

            do {
                let engine = try activeEngine()
                let pattern = try pattern(for: kind)
                let player = try engine.makePlayer(with: pattern)
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

        private func pattern(for kind: RestHapticKind) throws -> CHHapticPattern {
            let event: CHHapticEvent
            switch kind {
            case .lightTap:
                event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
                    ],
                    relativeTime: 0
                )
            case .expiryBuzz:
                event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
                    ],
                    relativeTime: 0,
                    duration: 0.65
                )
            }

            return try CHHapticPattern(events: [event], parameters: [])
        }
    #else
        func play(_: RestHapticKind) {}
    #endif
}

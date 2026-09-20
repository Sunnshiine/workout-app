import CoreHaptics
import Foundation

/// Every haptic the app plays, and the Core Haptics pattern each one is. Adding a haptic means
/// adding a case here, not a second engine.
enum Haptic: Equatable, Sendable {
    /// A rest-timer cue, one per `RestHapticEvent` the schedule makes due.
    case rest(RestHapticKind)

    /// The Move On ceremony's one Crisp pattern (DESIGN.md §7). The values are timed to the
    /// animation, not chosen for feel alone. The swell rises through the stem's climb (1.0s) and
    /// the peak transient lands as the bird drops to the branch tip (1.1s). Every Move On plays
    /// this same pattern.
    case moveOn

    func pattern() throws -> CHHapticPattern {
        switch self {
        case .rest(.lightTap):
            return try CHHapticPattern(
                events: [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
                        ],
                        relativeTime: 0
                    )
                ],
                parameters: []
            )

        case .rest(.expiryBuzz):
            return try CHHapticPattern(
                events: [
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
                        ],
                        relativeTime: 0,
                        duration: 0.65
                    )
                ],
                parameters: []
            )

        case .moveOn:
            return try Self.moveOnPattern()
        }
    }

    private static func moveOnPattern() throws -> CHHapticPattern {
        let swell = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30)
            ],
            relativeTime: 0,
            duration: Theme.Motion.ceremonyStem
        )

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
}

enum HapticError: Error, Equatable {
    case unsupportedHardware
}

/// The Core Haptics surface `HapticPlayer` needs. `CHHapticEngine` already has these two members;
/// the protocol exists so the player's engine lifecycle can be exercised off-device.
protocol HapticEngine: AnyObject {
    func start() throws
    func makePlayer(with pattern: CHHapticPattern) throws -> CHHapticPatternPlayer
}

extension CHHapticEngine: HapticEngine {}

/// Owns one lazily started haptic engine and plays `Haptic` patterns through it. A running engine
/// is reused. Any failure discards it, so the next play builds a fresh one rather than staying
/// silent for the rest of the session.
@MainActor
final class HapticPlayer {
    private let makeEngine: @MainActor () throws -> HapticEngine
    private var engine: HapticEngine?

    init(makeEngine: @escaping @MainActor () throws -> HapticEngine = HapticPlayer.hardwareEngine) {
        self.makeEngine = makeEngine
    }

    func play(_ haptic: Haptic) {
        do {
            let player = try activeEngine().makePlayer(with: haptic.pattern())
            try player.start(atTime: 0)
        } catch {
            engine = nil
        }
    }

    private func activeEngine() throws -> HapticEngine {
        if let engine { return engine }

        let engine = try makeEngine()
        try engine.start()
        self.engine = engine
        return engine
    }

    private static func hardwareEngine() throws -> HapticEngine {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            throw HapticError.unsupportedHardware
        }

        return try CHHapticEngine()
    }
}

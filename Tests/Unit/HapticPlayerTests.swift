import CoreHaptics
import Foundation
import Testing

@testable import WorkoutTracker

/// Ordering-stable rendering of `CHHapticPattern.exportDictionary()`, so a pattern can be
/// asserted against a literal.
private func canonical(_ value: Any) -> String {
    if let dictionary = value as? [AnyHashable: Any] {
        let pairs = dictionary.keys
            .map { "\($0)" }
            .sorted()
            .map { key -> String in
                let entry = dictionary.first { "\($0.key)" == key }!
                return "\(key)=\(canonical(entry.value))"
            }
        return "{" + pairs.joined(separator: ",") + "}"
    }
    if let array = value as? [Any] {
        return "[" + array.map(canonical).joined(separator: ",") + "]"
    }
    if let number = value as? NSNumber {
        return String(format: "%.6f", number.doubleValue)
    }
    return "\(value)"
}

private func exported(_ haptic: Haptic) throws -> String {
    canonical(try haptic.pattern().exportDictionary())
}

@Suite struct HapticPatternTests {
    @Test func lightTapIsASingleSoftTransient() throws {
        #expect(
            try exported(.rest(.lightTap)) == """
                {CHHapticPatternKey(_rawValue: Pattern)=[{Event={EventDuration=0.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=0.350000},\
                {ParameterID=HapticSharpness,ParameterValue=0.450000}],\
                EventType=HapticTransient,Time=0.000000}}]}
                """
        )
    }

    @Test func inputIsOneTransientAtItsTuning() throws {
        #expect(
            try exported(.input(Theme.Haptics.logTap)) == """
                {CHHapticPatternKey(_rawValue: Pattern)=[{Event={EventDuration=0.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=1.000000},\
                {ParameterID=HapticSharpness,ParameterValue=0.650000}],\
                EventType=HapticTransient,Time=0.000000}}]}
                """
        )
    }

    @Test func warningIsTwoTransients120msApart() throws {
        #expect(
            try exported(.warning) == """
                {CHHapticPatternKey(_rawValue: Pattern)=[{Event={EventDuration=0.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=0.800000},\
                {ParameterID=HapticSharpness,ParameterValue=0.500000}],\
                EventType=HapticTransient,Time=0.000000}},{Event={EventDuration=0.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=0.600000},\
                {ParameterID=HapticSharpness,ParameterValue=0.500000}],\
                EventType=HapticTransient,Time=0.120000}}]}
                """
        )
    }

    @Test func expiryBuzzIsA650msContinuousEvent() throws {
        #expect(
            try exported(.rest(.expiryBuzz)) == """
                {CHHapticPatternKey(_rawValue: Pattern)=[{Event={EventDuration=0.650000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=0.650000},\
                {ParameterID=HapticSharpness,ParameterValue=0.350000}],\
                EventType=HapticContinuous,Time=0.000000}}]}
                """
        )
    }

    @Test func moveOnIsASwellCurvingIntoAPeakWhenTheBirdLands() throws {
        #expect(
            try exported(.moveOn) == """
                {CHHapticPatternKey(_rawValue: Pattern)=[{Event={EventDuration=1.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=0.350000},\
                {ParameterID=HapticSharpness,ParameterValue=0.300000}],\
                EventType=HapticContinuous,Time=0.000000}},{Event={EventDuration=0.000000,\
                EventParameters=[{ParameterID=HapticIntensity,ParameterValue=1.000000},\
                {ParameterID=HapticSharpness,ParameterValue=0.650000}],\
                EventType=HapticTransient,Time=1.450000}},{ParameterCurve=\
                {ParameterCurveControlPoints=[{ParameterValue=0.200000,Time=0.000000},\
                {ParameterValue=1.000000,Time=1.000000}],ParameterID=HapticIntensityControl,\
                Time=0.000000}}]}
                """
        )
    }

    @Test func everyRestScheduleKindHasAPattern() throws {
        let kinds = RestHapticSchedule(duration: 10).events.map(\.kind)

        for kind in Set(kinds) {
            #expect(throws: Never.self) { try Haptic.rest(kind).pattern() }
        }
        #expect(Set(kinds) == [.lightTap, .expiryBuzz])
    }
}

private struct EngineFailure: Error {}

private final class RecordingEngine: HapticEngine {
    private(set) var startCount = 0
    private(set) var startedPatterns: [CHHapticPattern] = []
    var makePlayerError: Error?

    func start() throws {
        startCount += 1
    }

    func makePlayer(with pattern: CHHapticPattern) throws -> CHHapticPatternPlayer {
        if let makePlayerError { throw makePlayerError }
        startedPatterns.append(pattern)
        return RecordingPlayer()
    }
}

private final class RecordingPlayer: NSObject, CHHapticPatternPlayer {
    var isMuted = false
    func start(atTime time: TimeInterval) throws {}
    func stop(atTime time: TimeInterval) throws {}
    func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime time: TimeInterval) throws {}
    func scheduleParameterCurve(_ parameterCurve: CHHapticParameterCurve, atTime time: TimeInterval) throws {}
    func cancel() throws {}
}

@MainActor
@Suite struct HapticPlayerEngineTests {
    @Test func playStartsTheEngineOnceAndReusesItAcrossHaptics() throws {
        let engine = RecordingEngine()
        let player = HapticPlayer(makeEngine: { engine })

        player.play(.rest(.lightTap))
        player.play(.moveOn)

        #expect(engine.startCount == 1)
        #expect(engine.startedPatterns.count == 2)
        #expect(try canonical(engine.startedPatterns[1].exportDictionary()) == exported(.moveOn))
    }

    @Test func aFailedPlayDiscardsTheEngineSoTheNextPlayBuildsAFreshOne() throws {
        let failing = RecordingEngine()
        failing.makePlayerError = EngineFailure()
        let healthy = RecordingEngine()
        var engines = [failing, healthy]
        let player = HapticPlayer(makeEngine: { engines.removeFirst() })

        player.play(.rest(.lightTap))
        player.play(.rest(.expiryBuzz))

        #expect(failing.startedPatterns.isEmpty)
        #expect(healthy.startCount == 1)
        #expect(try canonical(healthy.startedPatterns[0].exportDictionary()) == exported(.rest(.expiryBuzz)))
    }

    @Test func anEngineThatCannotBeBuiltLeavesThePlayerSilentAndRetrying() throws {
        var attempts = 0
        let player = HapticPlayer(makeEngine: {
            attempts += 1
            throw EngineFailure()
        })

        player.play(.moveOn)
        player.play(.moveOn)

        #expect(attempts == 2)
    }
}

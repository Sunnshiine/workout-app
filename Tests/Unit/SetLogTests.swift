import Foundation
import Testing

@testable import WorkoutTracker

@Test func setLogFormatsWeightedAndBodyweight() {
    let weighted = SetLog(weight: .pounds(185), reps: 7, rpe: .six)
    #expect(weighted.formatted == "185x7@6")

    let bw = SetLog(weight: .bodyweight, reps: 12, rpe: .seven)
    #expect(bw.formatted == "BWx12@7")
}

@Test func setLogFormatsHalfPointRPEWithItsDecimalAndWholePointWithout() {
    #expect(SetLog(weight: .pounds(185), reps: 5, rpe: .eightPointFive).formatted == "185x5@8.5")
    #expect(SetLog(formatted: "185x5@8.0")?.formatted == "185x5@8")
}

@Test func setLogParsingKeepsOffScaleRecordedRPE() {
    #expect(SetLog(formatted: "185x7@4")?.formatted == "185x7@4")
    #expect(SetLog(formatted: "185x7@7.25")?.formatted == "185x7@7.25")
    #expect(SetLog(formatted: "185x7@1e19")?.formatted == "185x7@1e+19")
    #expect(SetLog(formatted: "185x7@nan") == nil)
    #expect(SetLog(formatted: "185x7@inf") == nil)
}

@Test func setLogDecodesPersistedJSONAndEncodesRPEAsABareNumber() throws {
    let persisted = Data(#"{"weight":{"pounds":{"_0":185}},"reps":5,"rpe":8.5}"#.utf8)
    #expect(try JSONDecoder().decode(SetLog.self, from: persisted) == SetLog(weight: .pounds(185), reps: 5, rpe: .eightPointFive))

    let encoded = try JSONEncoder().encode(SetLog(weight: .bodyweight, reps: 12, rpe: .seven))
    let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["rpe"] as? Double == 7)
}

@Test func weightDropsTrailingZero() {
    #expect(Weight.pounds(182.5).label == "182.5")
    #expect(Weight.pounds(185).label == "185")
}

@MainActor
@Test func setDisplayUsesLoggedSetLogWhenPresent() throws {
    let logged = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE8", percentOneRM: nil, state: .logged)
    logged.setLog = SetLog(weight: .pounds(25), reps: 12, rpe: .seven)

    #expect(logged.displayReps == "25x12@7")
    #expect(logged.displayLoad == nil)

    let pending = ExerciseSet(index: 1, prescribedReps: "10", prescribedLoad: "RPE9", percentOneRM: nil, state: .pending)
    #expect(pending.displayReps == "10")
    #expect(pending.displayLoad == "RPE9")
}

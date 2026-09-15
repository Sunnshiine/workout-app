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

@Test func setLogParsingRejectsRPEOffTheTenPointScale() {
    for token in ["4", "5.5", "7.25", "11", "1e19", "nan", "inf"] {
        #expect(SetLog(formatted: "185x7@\(token)") == nil)
    }
}

@Test func rpeScaleIsTheTenRailPointsInOrderAndEachLabelRoundTrips() {
    #expect(RPE.allCases.map(\.label) == ["5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10"])
    for rpe in RPE.allCases {
        #expect(SetLog(formatted: "185x5@\(rpe.label)")?.rpe == rpe)
    }
}

@Test func setLogDecodesPersistedJSONAndEncodesRPEAsABareNumber() throws {
    let persisted = Data(#"{"weight":{"pounds":{"_0":185}},"reps":5,"rpe":8.5}"#.utf8)
    #expect(try JSONDecoder().decode(SetLog.self, from: persisted) == SetLog(weight: .pounds(185), reps: 5, rpe: .eightPointFive))

    let encoded = try JSONEncoder().encode(SetLog(weight: .bodyweight, reps: 12, rpe: .seven))
    let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["rpe"] as? Double == 7)
}

@MainActor
@Test func persistedSetLogWithAnOffScaleRPEDoesNotDecode() {
    let persisted = Data(#"{"weight":{"pounds":{"_0":185}},"reps":5,"rpe":5.5}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(SetLog.self, from: persisted) }

    let cached = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    cached.setLogData = persisted
    #expect(cached.setLog == nil)
    #expect(cached.displayReps == "5")
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

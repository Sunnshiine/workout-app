import Testing

@testable import WorkoutTracker

@Suite struct PlateLoadTests {
    private func inventory(_ bar: Bar = .standard, plates: [PlateDenomination] = PlateDenomination.allCases) -> PlateInventory {
        PlateInventory(bar: bar, plates: Set(plates))
    }

    @Test func theEmptyBarCarriesNothing() throws {
        let load = try #require(PlateLoad(weighing: 45, on: inventory()))
        #expect(load.perSide.isEmpty)
        #expect(load.reachable == 45)
        #expect(load.remainder == 0)
    }

    @Test func threePlatesASideMakeThreeFifteen() throws {
        let load = try #require(PlateLoad(weighing: 315, on: inventory()))
        #expect(load.perSide == [.fortyFive, .fortyFive, .fortyFive])
        #expect(load.reachable == 315)
        #expect(load.remainder == 0)
    }

    @Test func loadsTheHeaviestPlatesFirst() throws {
        let load = try #require(PlateLoad(weighing: 165, on: inventory()))
        #expect(load.perSide == [.fortyFive, .ten, .five])
        #expect(load.reachable == 165)
    }

    @Test func fallsToTheNearestLoadableWeightBelowAndSaysByHowMuch() throws {
        let load = try #require(PlateLoad(weighing: 237.5, on: inventory()))
        #expect(load.perSide == [.fortyFive, .fortyFive, .five])
        #expect(load.reachable == 235)
        #expect(load.remainder == 2.5)
    }

    @Test func withoutTwoAndAHalfsFortySevenAndAHalfIsTheBar() throws {
        let load = try #require(PlateLoad(weighing: 47.5, on: inventory(plates: [.fortyFive, .thirtyFive, .twentyFive, .ten, .five])))
        #expect(load.perSide.isEmpty)
        #expect(load.reachable == 45)
        #expect(load.remainder == 2.5)
    }

    @Test func aGymOfBigPlatesStillFindsTheExactLoadGreedyWouldMiss() throws {
        let tens = try #require(PlateLoad(weighing: 105, on: inventory(plates: [.fortyFive, .thirtyFive, .twentyFive, .ten])))
        #expect(tens.perSide == [.ten, .ten, .ten])
        #expect(tens.remainder == 0)

        let quarters = try #require(PlateLoad(weighing: 145, on: inventory(plates: [.fortyFive, .twentyFive])))
        #expect(quarters.perSide == [.twentyFive, .twentyFive])
        #expect(quarters.remainder == 0)
    }

    @Test func noPlatesAtAllLoadsTheBarAloneAtAnyWeight() throws {
        let load = try #require(PlateLoad(weighing: 315, on: inventory(plates: [])))
        #expect(load.perSide.isEmpty)
        #expect(load.reachable == 45)
        #expect(load.remainder == 270)
    }

    @Test func thousandAndFiveNeedsTwelvePlatesASide() throws {
        let load = try #require(PlateLoad(weighing: 1005, on: inventory()))
        #expect(load.perSide == Array(repeating: .fortyFive, count: 10) + [.twentyFive, .five])
        #expect(load.reachable == 1005)
    }

    @Test func aFifteenKiloBarCountsAsThirtyThreePounds() throws {
        let load = try #require(PlateLoad(weighing: 183, on: inventory(.fifteenKilo)))
        #expect(load.perSide == [.fortyFive, .twentyFive, .five])
        #expect(load.reachable == 183)
    }

    @Test func aWeightTheBarAloneOutweighsHasNoLoad() {
        #expect(PlateLoad(weighing: 44.75, on: inventory()) == nil)
        #expect(PlateLoad(weighing: 0, on: inventory()) == nil)
        #expect(PlateLoad(weighing: -45, on: inventory()) == nil)
    }

    @Test func aTypoPastAnythingABarHoldsHasNoLoad() {
        #expect(PlateLoad(weighing: 2000, on: inventory()) != nil)
        #expect(PlateLoad(weighing: 2000.5, on: inventory()) == nil)
        #expect(PlateLoad(weighing: 999_999_999, on: inventory()) == nil)
    }
}

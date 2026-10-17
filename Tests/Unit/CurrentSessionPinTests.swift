import Observation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeBlock(tabName: String = "Block 27") -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: tabName,
            weeks: (1...2).map { week in
                ParsedWeek(
                    number: week,
                    days: (1...4).map { day in
                        ParsedSession(
                            dayNumber: day,
                            date: nil,
                            exercises: [
                                ParsedExercise(
                                    name: "Squat",
                                    coachNote: nil,
                                    sets: [
                                        ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)
                                    ]
                                )
                            ]
                        )
                    }
                )
            }
        )
    )
}

@MainActor
private func session(_ week: Int, _ day: Int, in block: Block) throws -> Session {
    try #require(block.session(at: SessionAddress(week: week, day: day)))
}

@MainActor
@Test func withNoPinSheetDerivedProgressIsTheCurrentSession() throws {
    let block = makeBlock()
    try session(1, 3, in: block).exercises[0].sets[0].state = .logged

    let resolution = CurrentSessionPin(defaults: .inMemory()).resolve(in: block)

    #expect(resolution.pin == .unset)
    #expect(resolution.session?.address == SessionAddress(week: 1, day: 3))
    #expect(resolution.sheetDerivedSession?.address == SessionAddress(week: 1, day: 3))
    #expect(!resolution.hasPin)
    #expect(!resolution.isMadeCurrent)
}

@MainActor
@Test func aMoveOnPinIsInForceButIsNotMadeCurrent() throws {
    let block = makeBlock()
    let pin = CurrentSessionPin(defaults: .inMemory())

    pin.pin(try session(2, 1, in: block), in: block, by: .moveOn)
    let resolution = pin.resolve(in: block)

    #expect(resolution.pin == .inForce(.moveOn))
    #expect(resolution.session?.address == SessionAddress(week: 2, day: 1))
    #expect(resolution.sheetDerivedSession?.address == SessionAddress(week: 1, day: 1))
    #expect(resolution.hasPin)
    #expect(!resolution.isMadeCurrent)
}

@MainActor
@Test func aMadeCurrentPinBehindLoggedProgressWins() throws {
    let block = makeBlock()
    try session(1, 3, in: block).exercises[0].sets[0].state = .logged
    let pin = CurrentSessionPin(defaults: .inMemory())

    pin.pin(try session(1, 2, in: block), in: block, by: .madeCurrent)
    let resolution = pin.resolve(in: block)

    #expect(resolution.pin == .inForce(.madeCurrent))
    #expect(resolution.session?.address == SessionAddress(week: 1, day: 2))
    #expect(resolution.isMadeCurrent)
}

@MainActor
@Test func aPinThatMatchesNoSessionFallsBackToSheetDerivedProgress() throws {
    let block = makeBlock()
    try session(1, 3, in: block).exercises[0].sets[0].state = .logged
    let defaults = AppDefaults.inMemory()
    defaults.set(99, forKey: "advancedToOrderV2_Block 27")

    let resolution = CurrentSessionPin(defaults: defaults).resolve(in: block)

    #expect(resolution.pin == .noLongerResolves(.moveOn))
    #expect(resolution.session?.address == SessionAddress(week: 1, day: 3))
    #expect(resolution.hasPin)
}

@MainActor
@Test func aPinNamingAnUnavailableSessionFallsBackToSheetDerivedProgress() throws {
    let block = makeBlock()
    let pinned = try session(1, 2, in: block)
    let pin = CurrentSessionPin(defaults: .inMemory())
    pin.pin(pinned, in: block, by: .madeCurrent)

    pinned.exercises = []
    let resolution = pin.resolve(in: block)

    #expect(resolution.pin == .unavailable(pinned, .madeCurrent))
    #expect(resolution.session?.address == SessionAddress(week: 1, day: 1))
    #expect(!resolution.isMadeCurrent)
    #expect(resolution.hasPin)
}

@MainActor
@Test func thePinIsStoredInTheV2OrderEncoding() throws {
    let block = makeBlock()
    let defaults = AppDefaults.inMemory()
    let pin = CurrentSessionPin(defaults: defaults)

    pin.pin(try session(2, 1, in: block), in: block, by: .moveOn)
    #expect(defaults.integer(forKey: "advancedToOrderV2_Block 27") == 8)
    #expect(defaults.keys == ["advancedToOrderV2_Block 27"])

    pin.pin(try session(1, 2, in: block), in: block, by: .madeCurrent)
    #expect(defaults.integer(forKey: "advancedToOrderV2_Block 27") == 2)
}

@MainActor
@Test func aPinStoredByAnEarlierBuildResolvesAsAMoveOn() throws {
    let block = makeBlock()
    let defaults = AppDefaults.inMemory()
    defaults.set(8, forKey: "advancedToOrderV2_Block 27")

    let resolution = CurrentSessionPin(defaults: defaults).resolve(in: block)

    #expect(resolution.pin == .inForce(.moveOn))
    #expect(resolution.session?.address == SessionAddress(week: 2, day: 1))
}

@MainActor
@Test func aMadeCurrentPinOutlivesItsInstanceUntilAMoveOnReplacesIt() throws {
    let block = makeBlock()
    let defaults = AppDefaults.inMemory()
    CurrentSessionPin(defaults: defaults).pin(try session(1, 3, in: block), in: block, by: .madeCurrent)

    let relaunched = CurrentSessionPin(defaults: defaults)
    #expect(relaunched.resolve(in: block).pin == .inForce(.madeCurrent))

    relaunched.pin(try session(1, 4, in: block), in: block, by: .moveOn)
    #expect(relaunched.resolve(in: block).pin == .inForce(.moveOn))
}

@MainActor
@Test func aMoveOnOntoTheSessionMadeCurrentReadsAsAMoveOn() throws {
    // Make current W1 D3, then the coach empties it: Move On skips it. Once it is Available
    // again a Move On can land on it, and that advance is not the athlete's choice.
    let block = makeBlock()
    let pin = CurrentSessionPin(defaults: .inMemory())
    let day3 = try session(1, 3, in: block)
    pin.pin(day3, in: block, by: .madeCurrent)

    pin.pin(day3, in: block, by: .moveOn)

    #expect(pin.resolve(in: block).pin == .inForce(.moveOn))
}

@MainActor
@Test func anOrderRewrittenWithoutItsMarkerReadsAsAMoveOn() throws {
    // A build that predates the Made Current marker writes only the order on Move On.
    let block = makeBlock()
    let defaults = AppDefaults.inMemory()
    CurrentSessionPin(defaults: defaults).pin(try session(1, 3, in: block), in: block, by: .madeCurrent)

    defaults.set(4, forKey: "advancedToOrderV2_Block 27")

    #expect(CurrentSessionPin(defaults: defaults).resolve(in: block).pin == .inForce(.moveOn))
}

@MainActor
@Test func clearingOneBlockTabsPinLeavesAnotherTabsPin() throws {
    let block27 = makeBlock(tabName: "Block 27")
    let block28 = makeBlock(tabName: "Block 28")
    let defaults = AppDefaults.inMemory()
    let pin = CurrentSessionPin(defaults: defaults)
    pin.pin(try session(1, 2, in: block27), in: block27, by: .madeCurrent)
    pin.pin(try session(1, 3, in: block28), in: block28, by: .madeCurrent)

    pin.clear(in: block27)

    #expect(pin.resolve(in: block27).pin == .unset)
    #expect(pin.resolve(in: block28).session?.address == SessionAddress(week: 1, day: 3))
    #expect(defaults.keys == ["advancedToOrderV2_Block 28", "madeCurrentOrderV2_Block 28"])
}

@MainActor
@Test func aPinUnderEitherOrderEncodingCountsAsStoredAppState() {
    let defaults = AppDefaults.inMemory()
    #expect(!CurrentSessionPin.isStored(in: defaults))

    defaults.set(8, forKey: "advancedToOrder_Block 27")
    #expect(CurrentSessionPin.isStored(in: defaults))

    defaults.removeValue(forKey: "advancedToOrder_Block 27")
    defaults.set(8, forKey: "advancedToOrderV2_Block 27")
    #expect(CurrentSessionPin.isStored(in: defaults))
}

@MainActor
private final class ResolutionChanges {
    private(set) var count = 0

    init(watching pin: CurrentSessionPin, in block: Block) {
        withObservationTracking {
            _ = pin.resolve(in: block)
        } onChange: {
            MainActor.assumeIsolated { self.count += 1 }
        }
    }
}

@MainActor
@Test func clearingAPinNotifiesAReaderEvenWhenTheCurrentSessionStays() throws {
    let block = makeBlock()
    let pin = CurrentSessionPin(defaults: .inMemory())
    pin.pin(try session(1, 1, in: block), in: block, by: .madeCurrent)
    let changes = ResolutionChanges(watching: pin, in: block)

    pin.clear(in: block)

    #expect(changes.count == 1)
}

@MainActor
@Test func everySessionOfTheBlockCanBePinned() {
    let block = makeBlock()
    let pin = CurrentSessionPin(defaults: .inMemory())

    for pinned in block.weeks.flatMap(\.sessions) {
        pin.pin(pinned, in: block, by: .madeCurrent)
        #expect(pin.resolve(in: block).session?.persistentModelID == pinned.persistentModelID)
    }
}

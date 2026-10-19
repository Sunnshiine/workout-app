import Testing

@testable import WorkoutTracker

@MainActor
@Test func anOperationThatFinishesFirstGivesItsValue() async {
    let clock = ManualListeningClock()
    let operation = HeldCall()
    let work = Task { @MainActor in
        await operation.hold()
        return 7
    }

    let waiting = Task { await BoundedWait.wait(for: work, until: .seconds(10), on: clock) }
    await clock.waitUntilSleeping(until: .seconds(10), orRecord: "The wait never watched the deadline")
    operation.release()

    #expect(await waiting.value == 7)
}

@MainActor
@Test func theDeadlineGivesNilAndLetsTheOperationRunOn() async {
    let clock = ManualListeningClock()
    let operation = HeldCall()
    let work = Task { @MainActor in
        await operation.hold()
        return 7
    }

    let waiting = Task { await BoundedWait.wait(for: work, until: .seconds(10), on: clock) }
    await clock.waitUntilSleeping(until: .seconds(10), orRecord: "The wait never watched the deadline")
    clock.advance(by: .seconds(10))

    #expect(await waiting.value == nil)
    #expect(operation.isHeld, "the operation runs on")
    operation.release()
    #expect(await work.value == 7)
}

@MainActor
@Test func aDeadlineAlreadyPastIsNilAtOnceEvenForAFinishedOperation() async {
    let clock = ManualListeningClock()
    let work = Task { @MainActor in 7 }
    _ = await work.value
    clock.advance(by: .seconds(2))

    #expect(await BoundedWait.wait(for: work, until: .seconds(1), on: clock) == nil)
}

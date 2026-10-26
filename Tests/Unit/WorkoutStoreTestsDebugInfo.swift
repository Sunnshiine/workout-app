import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func currentSessionDebugInfoShowsSheetDerivedResolutionWhenNoPin() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))

    let info = store.currentSessionDebugInfo

    #expect(info.currentBlockTab == "Block 27")
    #expect(info.sheetDerivedSession == "Week 1, Day 3")
    #expect(info.pinnedSession == "None")
    #expect(info.viewedSession == "Week 1, Day 1")
    #expect(info.resolvedCurrentSession == "Week 1, Day 3")
    #expect(info.reason == "No Current Session Pin is set, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.copyText.contains("Sheet-derived Session: Week 1, Day 3"))
}

@MainActor
@Test func currentSessionDebugInfoShowsLocalOnlyPinWhenPresent() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])
    day3Set.state = .logged
    store.reload()

    store.show(SessionAddress(week: 1, day: 1))
    store.makeViewedSessionCurrent()

    let info = store.currentSessionDebugInfo

    #expect(info.sheetDerivedSession == "Week 1, Day 3")
    #expect(info.pinnedSession == "Week 1, Day 1 (Make current)")
    #expect(info.viewedSession == "Week 1, Day 1")
    #expect(info.resolvedCurrentSession == "Week 1, Day 1")
    #expect(info.reason == "The athlete made this Session current, so it wins over Sheet-derived progress.")
    #expect(info.localOnlyNote == "The Current Session Pin is local-only and is not Sheet data.")
    #expect(info.canClearPin)
    #expect(info.copyText.contains("Current Session Pin: Week 1, Day 1 (Make current)"))
    #expect(info.copyText.contains("The Current Session Pin is local-only and is not Sheet data."))
}

@MainActor
@Test func currentSessionDebugInfoNarratesAMoveOnAsAPinNotAnOverride() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()

    let info = store.currentSessionDebugInfo
    #expect(info.pinnedSession == "Week 1, Day 2 (Move On)")
    #expect(info.resolvedCurrentSession == "Week 1, Day 2")
    #expect(info.reason == "Move On advanced to this Session, so it wins over Sheet-derived progress.")
    #expect(info.localOnlyNote == "The Current Session Pin is local-only and is not Sheet data.")
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesAPinOnASessionThatBecameUnavailable() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    store.show(SessionAddress(week: 1, day: 2))
    store.makeViewedSessionCurrent()

    let pinned = try #require(store.block?.session(at: SessionAddress(week: 1, day: 2)))
    pinned.exercises = []
    store.reload()

    let info = store.currentSessionDebugInfo
    #expect(store.currentSession?.dayNumber == 1)
    #expect(info.pinnedSession == "Week 1, Day 2, Unavailable (Make current)")
    #expect(info.resolvedCurrentSession == "Week 1, Day 1")
    #expect(info.reason == "The Current Session Pin names an Unavailable Session, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesAPinThatNoLongerMatchesTheBlock() throws {
    let defaults = AppDefaults.inMemory()
    defaults.set(99, forKey: "advancedToOrderV2_Block 27")
    let fixture = try makeStore(defaults: defaults)
    defer { withExtendedLifetime(fixture.container) {} }

    let info = fixture.store.currentSessionDebugInfo

    #expect(fixture.store.currentSession?.dayNumber == 1)
    #expect(info.pinnedSession == "Saved pin no longer matches this Block (Move On)")
    #expect(info.reason == "The Current Session Pin no longer matches this Block, so Sheet-derived progress wins.")
    #expect(info.localOnlyNote == nil)
    #expect(info.canClearPin)
}

@MainActor
@Test func currentSessionDebugInfoNarratesABlockWithNoAvailableSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let block = try #require(store.block)
    for session in block.weeks.flatMap(\.sessions) {
        session.exercises = []
    }
    store.reload()

    let info = store.currentSessionDebugInfo

    #expect(info.sheetDerivedSession == "None")
    #expect(info.resolvedCurrentSession == "None")
    #expect(info.reason == "No Sheet-derived Session is available for this Block.")
    #expect(!info.canClearPin)
}

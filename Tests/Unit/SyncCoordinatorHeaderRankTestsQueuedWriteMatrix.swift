import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct HeaderRankRefusal: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let headers: [String?]
    let notes: [String: String]
    let day: Int
    let setIndex: Int
    let lastError: String
    let rowScan: String
}

@MainActor
@Test(arguments: [
    HeaderRankRefusal(
        testDescription: "U2 swapped, K15 logged",
        headers: ["Day 2", "Day 1"],
        notes: ["K15": "185x5@8"],
        day: 1,
        setIndex: 1,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and reading Day 1 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U2q swapped",
        headers: ["Day 2", "Day 1"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and reading Day 1 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U3 Day 1 cleared, AQ15 logged",
        headers: [nil, "Day 2", "Day 3"],
        notes: ["AQ15": "185x5@8"],
        day: 2,
        setIndex: 1,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and reading Day 2 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U3q Day 1 cleared",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and reading Day 2 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U3r Day 1 cleared, rank 1",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and reading Day 1 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U4 middle cleared",
        headers: ["Day 1", nil, "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and reading Day 2 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "U5 gap",
        headers: ["Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and reading Day 2 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "Day 8 at rank 3",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 3,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 3 was queued by header rank, "
            + "and reading Day 3 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "rank 3 past the last header, which reads Day 3",
        headers: ["Day 1", "Day 3"],
        notes: [:],
        day: 3,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 3 was queued by header rank, "
            + "and reading Day 3 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 1",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and reading Day 1 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 2",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and reading Day 2 by rank and by header number does not give the same Session on this sheet."
    ),
    HeaderRankRefusal(
        testDescription: "rank and number both name no Day",
        headers: ["Day 1", "Day 2", "Day 3"],
        notes: [:],
        day: 4,
        setIndex: 0,
        lastError: "Day 4 was not found in the sheet",
        rowScan: "No row selected: Week 1, Day 4 was not found."
    )
])
private func flushRefusesAWriteQueuedByHeaderRankWhereItsRankAndNumberDisagree(
    _ refusal: HeaderRankRefusal
) async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(
        headerRankPendingWrite(
            createdAt: 1,
            day: refusal.day,
            dayNumbering: .legacyHeaderRank,
            setIndex: refusal.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: refusal.headers, notes: refusal.notes))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.isEmpty)
    #expect(sync.outcome == .writesRefused(["Squat: \(refusal.lastError)"]))
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [refusal.lastError])
    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus) == [.conflict])
    #expect(entries.map(\.selectedA1Target) == [nil])
    #expect(entries.map(\.rowScanDetails) == [refusal.rowScan])
}

private struct QueuedWriteLanding: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let headers: [String?]
    let notes: [String: String]
    let day: Int
    let dayNumbering: DayNumbering
    let setIndex: Int
    let cell: String
    let value: String
}

@MainActor
@Test(arguments: [
    QueuedWriteLanding(
        testDescription: "U1 headed in order",
        headers: ["Day 1", "Day 2", "Day 3"],
        notes: ["AA15": "185x5@8"],
        day: 2,
        dayNumbering: .legacyHeaderRank,
        setIndex: 1,
        cell: "AA15",
        value: "185x5@8, 190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "U6 Day 1 repeated, rank 3",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 3,
        dayNumbering: .legacyHeaderRank,
        setIndex: 0,
        cell: "AQ15",
        value: "190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "Day 8 at rank 3, rank 2",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 2,
        dayNumbering: .legacyHeaderRank,
        setIndex: 0,
        cell: "AA15",
        value: "190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "a header-number write on swapped headers",
        headers: ["Day 2", "Day 1"],
        notes: [:],
        day: 1,
        dayNumbering: .headerNumber,
        setIndex: 0,
        cell: "AA15",
        value: "190x5@8"
    )
])
private func flushLandsAQueuedWriteWhereItsDayNamesOneSession(_ landing: QueuedWriteLanding) async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(
        headerRankPendingWrite(
            createdAt: 1,
            day: landing.day,
            dayNumbering: landing.dayNumbering,
            setIndex: landing.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: landing.headers, notes: landing.notes))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: landing.cell, value: landing.value)])
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

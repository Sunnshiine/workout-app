import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func loadsBlockAndDefaultsDisplayedToCurrent() throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...1).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(dayNumber: d, date: nil, exercises: [])
                }
            )
        }
    )
    ctx.insert(BlockBuilder.makeBlock(from: parsed))
    try ctx.save()

    let store = WorkoutStore(context: ctx)
    store.reload()

    #expect(store.block?.tabName == "Block 27")
    #expect(store.displayedSession?.dayNumber == 1)  // defaults to current
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
}

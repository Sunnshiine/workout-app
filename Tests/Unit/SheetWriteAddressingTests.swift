import Foundation
import Testing

@testable import WorkoutTracker

/// Pins every `SheetWriterError` the write planner raises while addressing a request, before the
/// Set-Log placement rule gets a say, with the exact message the app shows.
private func addressingGrid(_ cells: [String: String] = [:], omitting: Set<String> = []) -> SheetGrid {
    let base = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
        "C15": "Squat", "D15": "2"
    ]
    let headers = base.filter { !omitting.contains($0.key) }
    return gridFromA1(headers.merging(cells) { _, new in new }, rows: 30, cols: 30)
}

private func addressingRequest(
    week: Int = 1,
    day: Int = 1,
    exerciseName: String = "Squat",
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes
) -> SheetWriteRequest {
    SheetWriteRequest(
        blockTab: "Block 27",
        week: week,
        day: day,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )
}

private func planError(
    _ request: SheetWriteRequest,
    grid: SheetGrid,
    rowVisibility: [Int: SheetRowVisibility] = [:]
) -> SheetWriterError? {
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: SheetSnapshot(values: grid, rowVisibility: rowVisibility))
    do {
        _ = try planner.plan(request, in: snapshot)
        return nil
    } catch let error as SheetWriterError {
        return error
    } catch {
        return nil
    }
}

@Test func refusesAWeekThatIsNotInTheSheet() {
    let error = planError(addressingRequest(week: 4), grid: addressingGrid())

    #expect(error == .weekNotFound(4))
    #expect(error?.errorDescription == "Week 4 was not found in the sheet")
}

@Test func refusesADayThatIsNotInTheWeek() {
    let error = planError(addressingRequest(day: 3), grid: addressingGrid())

    #expect(error == .dayNotFound(3))
    #expect(error?.errorDescription == "Day 3 was not found in the sheet")
}

@Test func refusesADayWhoseNumberTwoHeadersRead() {
    let error = planError(
        addressingRequest(),
        grid: addressingGrid(["S12": "Day 1", "T14": "Sets", "AA14": "Notes", "S15": "Squat", "T15": "2"])
    )

    #expect(error == .dayNotFound(1))
    #expect(error?.errorDescription == "Day 1 was not found in the sheet")
}

@Test func refusesAnExerciseThatIsNotInTheSession() {
    let error = planError(addressingRequest(exerciseName: "Deadlift"), grid: addressingGrid())

    #expect(error == .exerciseNotFound("Deadlift"))
    #expect(error?.errorDescription == "Deadlift was not found in the sheet")
}

@Test func refusesANotesWriteWhenTheSessionHasNoNotesColumn() {
    let error = planError(addressingRequest(), grid: addressingGrid(omitting: ["K14"]))

    #expect(error == .columnNotFound("Notes"))
    #expect(error?.errorDescription == "Notes column was not found")
}

@Test func refusesALastSetRPEWriteWhenTheSessionHasNoRPEColumn() {
    let error = planError(addressingRequest(column: .lastSetRPE), grid: addressingGrid(omitting: ["I14"]))

    #expect(error == .columnNotFound("Last set RPE"))
    #expect(error?.errorDescription == "Last set RPE column was not found")
}

@Test func refusesAMissingColumnBeforeAMissingExercise() {
    #expect(
        planError(addressingRequest(exerciseName: "Deadlift"), grid: addressingGrid(omitting: ["K14"]))
            == .columnNotFound("Notes")
    )
    #expect(
        planError(
            addressingRequest(exerciseName: "Deadlift", column: .lastSetRPE),
            grid: addressingGrid(omitting: ["I14"])
        ) == .columnNotFound("Last set RPE")
    )
}

// Before #559 this redirected onto the visible row below the hidden one and the log landed there.
@Test func refusesASetLogWriteWhenTheExerciseRowIsHidden() {
    let error = planError(
        addressingRequest(),
        grid: addressingGrid(["K15": "Keep elbows soft", "C18": "Bench", "D18": "1"]),
        rowVisibility: [14: SheetRowVisibility(hiddenByUser: true)]
    )

    #expect(error == .exerciseNotFound("Squat"))
    #expect(error?.errorDescription == "Squat was not found in the sheet")
}

@Test func refusesALastSetRPEWriteWhenTheExerciseRowIsHidden() {
    let error = planError(
        addressingRequest(column: .lastSetRPE),
        grid: addressingGrid(),
        rowVisibility: [14: SheetRowVisibility(hiddenByUser: true)]
    )

    #expect(error == .exerciseNotFound("Squat"))
    #expect(error?.errorDescription == "Squat was not found in the sheet")
}

@Test func writesLastSetRPEToTheAnchorRowWhenItIsVisible() throws {
    let planner = SheetWritePlanner()
    let update = try planner.plan(addressingRequest(column: .lastSetRPE), in: addressingGrid())

    #expect(update.range == "'Block 27'!I15")
    #expect(update.value == "185x5@8")
}

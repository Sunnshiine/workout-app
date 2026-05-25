import Testing

@testable import WorkoutTracker

@Test func resolvesRoleColumnsByHeaderScan() {
    // Day-1 role header row (real): D14 Sets, F14 Reps, G14 %1RM, H14 Load,
    // I14 Last set RPE, K14 Notes. Name column = day start (C).
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load",
            "I14": "Last set RPE", "K14": "Notes"
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let cols = resolveDayColumns(in: grid, section: section, dayIndex: 0)
    #expect(cols.name == 2)  // C
    #expect(cols.sets == 3)  // D
    #expect(cols.reps == 5)  // F
    #expect(cols.percentOneRM == 6)  // G
    #expect(cols.load == 7)  // H
    #expect(cols.lastSetRPE == 8)  // I
    #expect(cols.notes == 10)  // K
}

@Test func locatesFourDayGroupsPerWeekSection() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4"
        ],
        rows: 40,
        cols: 60
    )

    let sections = locateWeekSections(in: grid)
    #expect(sections.count == 2)
    #expect(sections[0].headerRow == 11)  // row 12 (0-based 11)
    #expect(sections[0].dayStartCols == [2, 18, 34, 49])  // C,S,AI,AX (0-based)
    #expect(sections[0].roleHeaderRow == 13)  // header + 2
}

@Test func splitsCadencePrefix() {
    #expect(splitCadence("2-3:1:0 BB RDL").cadence == "2-3:1:0")
    #expect(splitCadence("2-3:1:0 BB RDL").base == "BB RDL")
    #expect(splitCadence("0:3:0 Standing Calve Raises").base == "Standing Calve Raises")
    #expect(splitCadence("Lateral Raises").cadence == nil)
    #expect(splitCadence("Lateral Raises").base == "Lateral Raises")
}

@Test func parsesAnchorAndContinuationRows() {
    // Real rows: C15 anchor "0:3:0 Standing Calve Raises", D15 Sets=2, F15 Reps=12,
    // H15 Load "RPE9, RPE10", K15 coach/log "Superset cue". Next anchor C22.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10", "K15": "Superset cue",
            "C22": "0:2:0 Pull Up", "D22": "2", "F22": "AMRAP", "H22": "BW"
        ],
        rows: 30,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)
    #expect(exercises.count == 2)
    #expect(exercises[0].name == "0:3:0 Standing Calve Raises")
    #expect(exercises[0].baseName == "Standing Calve Raises")
    #expect(exercises[0].coachNote == "Superset cue")
    #expect(exercises[0].sets.count == 2)  // "2" sets
    #expect(exercises[0].sets[0].prescribedReps == "12")
    #expect(exercises[0].sets[0].prescribedLoad == "RPE9, RPE10")
    #expect(exercises[1].baseName == "Pull Up")
    #expect(exercises[1].sets[0].prescribedReps == "AMRAP")
    #expect(exercises[1].sets[0].prescribedLoad == "BW")
}

@Test func assemblesBlockFromTwoWeekSections() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10",
            "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4",
            "D39": "Sets", "F39": "Reps", "H39": "Load", "K39": "Notes",
            "C40": "0:3:0 Standing Calve Raises", "D40": "2", "F40": "11 - 12", "H40": "RPE9, RPE10"
        ],
        rows: 45,
        cols: 60
    )

    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    #expect(parsed.warnings.isEmpty)
    #expect(parsed.block.weeks.count == 2)
    #expect(parsed.block.weeks[0].number == 1)
    #expect(parsed.block.weeks[0].days.count == 4)
    #expect(parsed.block.weeks[0].days[0].exercises[0].baseName == "Standing Calve Raises")
    #expect(parsed.block.weeks[1].days[0].exercises[0].sets[0].prescribedReps == "11 - 12")
}

@Test func warnsWhenNoWeekSections() {
    let parsed = SheetParser().parse(grid: gridFromA1([:], rows: 5, cols: 5), tabName: "Block 27")
    #expect(parsed.warnings.contains { $0.contains("no week sections") })
}

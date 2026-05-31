import Testing

@testable import WorkoutTracker

@Test func resolvesRoleColumnsByHeaderScan() {
    // Day-1 role header row (real): D14 Sets, F14 Reps, G14 %1RM, H14 Load,
    // I14 Last set RPE, K14 Notes. Name column = day start (C).
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load",
            "I14": "Last set RPE", "K14": "Notes",
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
            "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4",
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

@Test func parsesTrainingMaxValuesFromHeaderArea() {
    let grid = gridFromA1(
        [
            "E6": "Training Max",
            "C7": "Squat", "E7": "365",
            "C8": "Bench Press", "E8": "245",
            "C9": "Deadlift", "E9": "455",
        ],
        rows: 20,
        cols: 10
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == 365)
    #expect(tm.bench == 245)
    #expect(tm.deadlift == 455)
}

@Test func parsesTrainingMaxValuesFromShiftedHeaderArea() {
    let grid = gridFromA1(
        [
            "G7": "Training Max",
            "E8": "Squat", "G8": "405",
            "E9": "Bench Press", "G9": "275",
            "E10": "Deadlift", "G10": "495",
        ],
        rows: 20,
        cols: 10
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == 405)
    #expect(tm.bench == 275)
    #expect(tm.deadlift == 495)
}

@Test func trainingMaxValuesAreNilWhenHeaderIsMissingOrValuesAreBlank() {
    let missingHeader = parseTrainingMax(from: gridFromA1([:], rows: 20, cols: 10))
    #expect(missingHeader.squat == nil)
    #expect(missingHeader.bench == nil)
    #expect(missingHeader.deadlift == nil)

    let blankValues = parseTrainingMax(
        from: gridFromA1(
            [
                "E6": "Training Max",
                "C7": "Squat", "E7": "",
                "C8": "Bench Press", "E8": " ",
                "C9": "Deadlift",
            ],
            rows: 20,
            cols: 10
        )
    )
    #expect(blankValues.squat == nil)
    #expect(blankValues.bench == nil)
    #expect(blankValues.deadlift == nil)
}

@Test func parsesAnchorAndContinuationRows() {
    // Real rows: C15 anchor "0:3:0 Standing Calve Raises", D15 Sets=2, F15 Reps=12,
    // H15 Load "RPE9, RPE10", K15 coach/log "Superset cue". Next anchor C22.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10", "K15": "Superset cue",
            "C22": "0:2:0 Pull Up", "D22": "2", "F22": "AMRAP", "H22": "BW",
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
    #expect(exercises[0].sets[0].prescribedLoad == "RPE9")
    #expect(exercises[0].sets[1].prescribedLoad == "RPE10")
    #expect(exercises[1].baseName == "Pull Up")
    #expect(exercises[1].sets[0].prescribedReps == "AMRAP")
    #expect(exercises[1].sets[0].prescribedLoad == "BW")
}

@Test func assemblesBlockFromTwoWeekSections() {
    let grid = gridFromA1(
        [
            "E6": "Training Max",
            "C7": "Squat", "E7": "365",
            "C8": "Bench Press", "E8": "245",
            "C9": "Deadlift", "E9": "455",
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10",
            "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4",
            "D39": "Sets", "F39": "Reps", "H39": "Load", "K39": "Notes",
            "C40": "0:3:0 Standing Calve Raises", "D40": "2", "F40": "11 - 12", "H40": "RPE9, RPE10",
        ],
        rows: 45,
        cols: 60
    )

    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    #expect(parsed.warnings.isEmpty)
    #expect(parsed.block.weeks.count == 2)
    #expect(parsed.block.squatTM == 365)
    #expect(parsed.block.benchTM == 245)
    #expect(parsed.block.deadliftTM == 455)
    #expect(parsed.block.weeks[0].number == 1)
    #expect(parsed.block.weeks[0].days.count == 4)
    #expect(parsed.block.weeks[0].days[0].exercises[0].baseName == "Standing Calve Raises")
    #expect(parsed.block.weeks[1].days[0].exercises[0].sets[0].prescribedReps == "11 - 12")
}

@Test func warnsWhenNoWeekSections() {
    let parsed = SheetParser().parse(grid: gridFromA1([:], rows: 5, cols: 5), tabName: "Block 27")
    #expect(parsed.warnings.contains { $0.contains("no week sections") })
}

@Test func perSetLoadAndRepsAreSplitByComma() {
    // Issue #7: comma-separated values (e.g. "RPE 9, 10") map one token per set,
    // repeating the last token when fewer tokens than sets.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load",
            // 2 sets, both fields have 2 comma-separated values
            "C15": "Squat", "D15": "2", "F15": "8, 10", "H15": "RPE 9, 10",
            // 3 sets, single value → repeats for all sets
            "C22": "Deadlift", "D22": "3", "F22": "5", "H22": "RPE 8",
        ],
        rows: 30,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]
    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    let squat = exercises[0]
    #expect(squat.sets[0].prescribedLoad == "RPE 9")
    #expect(squat.sets[1].prescribedLoad == "RPE 10")
    #expect(squat.sets[0].prescribedReps == "8")
    #expect(squat.sets[1].prescribedReps == "10")

    let deadlift = exercises[1]
    #expect(deadlift.sets[0].prescribedLoad == "RPE 8")
    #expect(deadlift.sets[1].prescribedLoad == "RPE 8")
    #expect(deadlift.sets[2].prescribedLoad == "RPE 8")
}

@Test func perSetLoadCarriesPrefixToShorthandCommaValues() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load",
            "C15": "Squat", "D15": "2", "F15": "8", "H15": "RPE 9, 10",
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]
    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets[0].prescribedLoad == "RPE 9")
    #expect(exercises[0].sets[1].prescribedLoad == "RPE 10")
}

@Test func continuationNotesBecomeSetLogsWithoutUsingAnchorCoachNote() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Chest Fly", "D15": "2", "F15": "12", "H15": "25", "K15": "Keep elbows soft",
            "K16": "25x12@7",
            "K17": "20x10@8",
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]
    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "Keep elbows soft")
    #expect(exercises[0].sets[0].setLog == SetLog(weight: .pounds(25), reps: 12, rpe: 7))
    #expect(exercises[0].sets[1].setLog == SetLog(weight: .pounds(20), reps: 10, rpe: 8))
}

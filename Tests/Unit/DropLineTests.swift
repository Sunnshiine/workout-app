import Testing

@testable import WorkoutTracker

/// One drop-set layout a coach writes under a `1 x 6` top Set at A1 row 15, with the next Exercise at
/// row 18. Columns: C name, D Sets, E `x`, F Reps, H Load, K Notes.
struct DropLayout: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let cells: [String: String]
    let hiddenRows: Set<Int>
    let squatSetCount: Int
    let prescribedLoads: [String]
    /// The 0-based row each Set's Set Log lands on.
    let setLogRows: [Int]

    init(
        _ name: String,
        _ cells: [String: String],
        hidden: Set<Int> = [],
        sets: Int = 3,
        loads: [String] = ["RPE8", "Drop 20%", "Drop 20%"],
        rows: [Int] = [14, 15, 15]
    ) {
        testDescription = name
        self.cells = cells
        hiddenRows = hidden
        squatSetCount = sets
        prescribedLoads = loads
        setLogRows = rows
    }
}

private let squat = ["C15": "HB SQ", "D15": "1", "E15": "x", "F15": "6", "H15": "RPE8", "K15": "175x6@8"]
private let nextLift = ["C18": "Next Lift", "D18": "2", "F18": "10", "H18": "RPE8"]
private let dropLine = ["D16": "2", "E16": "x", "F16": "8", "H16": "Drop 20%"]

private func layout(_ cells: [String: String]...) -> [String: String] {
    cells.reduce(into: squat.merging(nextLift) { $1 }) { $0.merge($1) { $1 } }
}

private let layouts: [DropLayout] = [
    DropLayout("one line per row", layout(dropLine)),
    DropLayout(
        "#1229: below rows the coach hid",
        layout(["C16": "Old Chest Press", "D16": "2", "F16": "12", "D17": "2", "F17": "8", "H17": "Drop 20%"]),
        hidden: [15],
        rows: [14, 16, 16]
    ),
    DropLayout("Sets cell blank", layout(dropLine, ["D16": ""]), sets: 2, loads: ["RPE8", "Drop 20%"], rows: [14, 15]),
    DropLayout("Sets cell x2", layout(dropLine, ["D16": "x2"])),
    DropLayout("2 x 8 in the Reps cell", layout(dropLine, ["D16": "", "E16": "", "F16": "2 x 8"])),
    DropLayout(
        "top Set and drops on one row",
        layout(["D15": "1+2", "F15": "6, 8, 8", "H15": "RPE8, Drop 20%"]),
        rows: [14, 14, 14]
    ),
    DropLayout(
        "top Set and drops on one row worded -20%",
        layout(["D15": "1+2", "F15": "6, 8, 8", "H15": "RPE8, -20%"]),
        loads: ["RPE8", "-20%", "-20%"],
        rows: [14, 14, 14]
    ),
    DropLayout("drop line named Drop", layout(dropLine, ["C16": "Drop"])),
    DropLayout("drop line named with an arrow", layout(dropLine, ["C16": "↳"])),
    DropLayout("drop line named after the lift", layout(dropLine, ["C16": "HB SQ Drop"])),
    DropLayout("worded 20% drop", layout(dropLine, ["H16": "20% drop"]), loads: ["RPE8", "20% drop", "20% drop"]),
    DropLayout("worded -20%", layout(dropLine, ["H16": "-20%"]), loads: ["RPE8", "-20%", "-20%"]),
    DropLayout("worded @80%", layout(dropLine, ["H16": "@80%"]), loads: ["RPE8", "@80%", "@80%"]),
    DropLayout(
        "below a blank row",
        layout(["D17": "2", "F17": "8", "H17": "Drop 20%"]),
        rows: [14, 16, 16]
    ),
    DropLayout("on a bench press", layout(dropLine, ["C15": "Comp BP"]))
]

private func parsedDay(_ cells: [String: String], hidden: Set<Int>) throws -> (SheetSnapshot, SheetLayoutDay, [ParsedExercise]) {
    let snapshot = SheetSnapshot(
        values: gridFromA1(
            ["C12": "Day 1", "S12": "Day 2", "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes"].merging(cells) { $1 },
            rows: 24,
            cols: 30
        ),
        rowVisibility: Dictionary(uniqueKeysWithValues: hidden.map { ($0, SheetRowVisibility(hiddenByUser: true)) })
    )
    let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(at: SessionAddress(week: 1, day: 1)))
    let parsed = SheetParser().parse(snapshot: snapshot, tabName: "Block - 32")
    return (snapshot, day, try #require(parsed.block.weeks.first?.days.first).exercises)
}

private func setLogRows(_ anchor: SheetLayoutExerciseAnchor, sets: Int, snapshot: SheetSnapshot, day: SheetLayoutDay) -> [Int?] {
    (0..<sets).map { setIndex in
        guard case .placed(let placement) = anchor.setLogPlacement(for: setIndex, in: snapshot, cols: day.columns)
        else { return nil }
        return placement.row
    }
}

@Test("A drop line shows as loggable Sets of the Exercise above it", arguments: layouts)
func aDropLineShowsAsLoggableSetsOfTheExerciseAboveIt(layout: DropLayout) throws {
    let (snapshot, day, exercises) = try parsedDay(layout.cells, hidden: layout.hiddenRows)

    #expect(exercises.map(\.exerciseName.entered) == [layout.cells["C15"] ?? "", "Next Lift"])
    let top = try #require(exercises.first)
    #expect(top.sets.count == layout.squatSetCount)
    #expect(top.sets.map(\.prescribedLoad) == layout.prescribedLoads)
    #expect(top.sets.first?.setLog == SetLog(weight: .pounds(175), reps: 6, rpe: .eight))
    #expect(top.sets.dropFirst().allSatisfy { $0.state == .pending })

    let rows = setLogRows(try #require(day.exerciseAnchors.first), sets: layout.squatSetCount, snapshot: snapshot, day: day)
    #expect(rows == layout.setLogRows)
    #expect(rows.allSatisfy { $0.map(snapshot.isRowVisible) == true })
}

@Test func aDropLineInTheRepsCellReadsItsRepsAfterTheCount() throws {
    let (_, _, exercises) = try parsedDay(layout(dropLine, ["D16": "", "E16": "", "F16": "2 x 8"]), hidden: [])

    #expect(exercises[0].sets.dropFirst().map { PrescribedReps($0.prescribedReps) } == [.target(8...8), .target(8...8)])
}

/// #1230, layout 1: a retired Hamstring Curl's name row is hidden, and its visible row below keeps a
/// Sets count and old Set Logs. They stay with the Hamstring Curl, not the Back Squat above.
@Test func aRetiredMovementsVisibleLineUnderItsHiddenNameIsNotTheExerciseAbovesSets() throws {
    let cells = [
        "C15": "Back Squat", "D15": "3", "F15": "5", "H15": "RPE7",
        "C16": "0:1:0 Hamstring Curl", "D16": "2", "F16": "10",
        "D17": "2", "F17": "10", "K17": "60x10@8, 60x10@8",
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [15])

    #expect(exercises.map(\.exerciseName.entered) == ["Back Squat", "2-3:1:0 BB RDL"])
    #expect(exercises[0].sets.map(\.state) == [.pending, .pending, .pending])
    let backSquat = try #require(day.exerciseAnchors.first)
    #expect(setLogRows(backSquat, sets: 3, snapshot: snapshot, day: day) == [14, 14, 14])
}

/// #1230, layout 2: Back Squat's Notes hold a Coach Note, the next named row is hidden, and the
/// visible row under it holds that movement's coach text. Back Squat's Set Logs have nowhere safe to
/// go, so the write is refused rather than read or overwrite the coach's text.
@Test func aProtectedHeadersScanDoesNotTakeAHiddenMovementsCoachText() throws {
    let cells = [
        "C15": "Back Squat", "D15": "3", "F15": "5", "H15": "RPE7", "K15": "Brace hard",
        "C16": "0:2:0 Hip Thrust", "D16": "2", "F16": "8",
        "K17": "Start w/ 10 sec hold",
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [15])

    #expect(exercises[0].sets.map(\.state) == [.pending, .pending, .pending])
    let backSquat = try #require(day.exerciseAnchors.first)
    #expect(backSquat.setLogPlacement(for: 0, in: snapshot, cols: day.columns) == .occupiedHeaderBlocksSetRow)
}

/// #1168's Leg Ext.: a blank visible row under hidden named rows stays the Exercise's spare row, and
/// keeps reading as its own once a Set Log lands there.
@Test func aSetLogUnderHiddenNamedRowsStaysWithTheExerciseAbove() throws {
    let cells = [
        "C15": "0:2:0 Leg Ext.", "D15": "1", "F15": "9", "H15": "RPE9", "K15": "Pause at the top",
        "C16": "0:2:0 Old Leg Curl", "D16": "2", "F16": "10",
        "K18": "105x9@9",
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (_, _, exercises) = try parsedDay(cells, hidden: [15, 16])

    #expect(exercises[0].sets.map(\.setLog) == [SetLog(weight: .pounds(105), reps: 9, rpe: .nine)])
}

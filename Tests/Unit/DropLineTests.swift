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
    DropLayout("worded 20% drop", layout(dropLine, ["H16": "20% drop"]), loads: ["RPE8", "20% drop", "20% drop"]),
    DropLayout("worded -20%", layout(dropLine, ["H16": "-20%"]), loads: ["RPE8", "-20%", "-20%"]),
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
    #expect(top.sets.dropFirst().allSatisfy { PrescribedReps($0.prescribedReps) == .target(8...8) })

    let rows = setLogRows(try #require(day.exerciseAnchors.first), sets: layout.squatSetCount, snapshot: snapshot, day: day)
    #expect(rows == layout.setLogRows)
    #expect(rows.allSatisfy { $0.map(snapshot.isRowVisible) == true })
}

@Test func aDropLineInTheRepsCellReadsItsRepsAfterTheCount() throws {
    let (_, _, exercises) = try parsedDay(layout(dropLine, ["D16": "", "E16": "", "F16": "2 x 8"]), hidden: [])

    #expect(exercises[0].sets.dropFirst().map { PrescribedReps($0.prescribedReps) } == [.target(8...8), .target(8...8)])
}

/// #1230, layout 1: a retired Hamstring Curl's name row is hidden, and its visible row below keeps a
/// Sets count and old Set Logs. A row holding a Set Log never retires, so Back Squat reads it as
/// main does, its Sets 4 and 5 logged, and every Set keeps its index and row.
@Test func aRetiredMovementsVisibleLineHoldingSetLogsReadsAsMainReadsIt() throws {
    let cells = [
        "C15": "Back Squat", "D15": "3", "F15": "5", "H15": "RPE7",
        "C16": "0:1:0 Hamstring Curl", "D16": "2", "F16": "10",
        "D17": "2", "F17": "10", "K17": "60x10@8, 60x10@8",
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (_, _, exercises) = try parsedDay(cells, hidden: [15])

    #expect(exercises.map(\.exerciseName.entered) == ["Back Squat", "2-3:1:0 BB RDL"])
    #expect(exercises[0].sets.map(\.state) == [.pending, .pending, .pending, .logged, .logged])
}

/// H7, after an update: the top Set's Coach Note sent its log to the free row below a hidden named
/// row and a Line the coach wrote under it. That log keeps the row from retiring, and the Line with
/// it, so the top Set still reads it, and no Set changes index.
@Test(arguments: [
    (["K18": "175x6@8"], [SetState.logged, .pending, .pending, .pending]),
    (["K18": "175x6@8", "D19": "2", "F19": "8", "H19": "RPE7"], [.logged, .pending, .pending, .pending, .pending, .pending])
])
func aSetLogBelowALineUnderAHiddenNameKeepsEveryRowFromRetiring(cells: [String: String], states: [SetState]) throws {
    let body = roomyLayout([
        "K15": "Brace", "C16": "Old Lift", "D16": "3", "F16": "8", "H16": "RPE7", "D17": "3", "F17": "10", "H17": "RPE7"
    ])
    let (_, _, exercises) = try parsedDay(body.merging(cells) { $1 }, hidden: [15])

    #expect(exercises[0].sets.map(\.state) == states)
    #expect(exercises[0].sets.first?.setLog == SetLog(weight: .pounds(175), reps: 6, rpe: .eight))
}

/// #1230, layout 2: Back Squat's Notes hold a Coach Note, the next named row is hidden, and the
/// visible row under it holds coach text. The app read that text as Back Squat's first Set Log
/// before it read Drop lines, and still does, so it writes there too. Refusing it would leave a Set
/// that reads Logged with no mark once the banner clears (#1247).
@Test func aHiddenMovementsCoachTextReadsAsTheExerciseAboveDid() throws {
    let cells = [
        "C15": "Back Squat", "D15": "3", "F15": "5", "H15": "RPE7", "K15": "Brace hard",
        "C16": "0:2:0 Hip Thrust", "D16": "2", "F16": "8",
        "K17": "Start w/ 10 sec hold",
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [15])

    #expect(exercises[0].sets.map(\.state) == [.logged, .pending, .pending])
    #expect(exercises[0].sets.first?.unstructuredSetLog == "Start w/ 10 sec hold")
    let backSquat = try #require(day.exerciseAnchors.first)
    guard case .placed(let placement) = backSquat.setLogPlacement(for: 0, in: snapshot, cols: day.columns) else {
        Issue.record("Set 1 has no row")
        return
    }
    #expect(placement.row == 16)
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

/// A drop row under rows the coach hid, whose Notes the athlete or coach already wrote in, stays the
/// Exercise's own: neither its Coach Note nor a hand-typed Set Log hands it to the hidden movement.
@Test(arguments: ["Stay tight", "140x8@8, 140x8 grindy"])
func aDropRowsOwnNotesUnderHiddenRowsKeepItsSets(notes: String) throws {
    let cells = layout(["C16": "Old Chest Press", "D16": "2", "F16": "12", "D17": "2", "F17": "8", "H17": "Drop 20%", "K17": notes])
    let (_, _, exercises) = try parsedDay(cells, hidden: [15])

    #expect(exercises[0].sets.map(\.prescribedLoad) == ["RPE8", "Drop 20%", "Drop 20%"])
}

/// #1168's Leg Ext. with hand-typed Set Logs on its spare row: they read as the Exercise's own.
@Test(arguments: [
    (1, "105x9 easy", [SetState.logged]),
    (1, "BWx8@8", [.logged]),
    (1, "BW+25x8@8", [.logged]),
    (1, "50kgx9@9", [.logged]),
    (1, "bar x 9", [.logged]),
    (3, "105x9@9, 105x9 grindy", [.logged, .logged, .pending])
])
func aHandTypedSetLogUnderHiddenNamedRowsStaysWithTheExerciseAbove(sets: Int, notes: String, states: [SetState]) throws {
    let cells = [
        "C15": "0:2:0 Leg Ext.", "D15": "\(sets)", "F15": "9", "H15": "RPE9", "K15": "Pause at the top",
        "C16": "0:2:0 Old Leg Curl", "D16": "2", "F16": "10",
        "K18": notes,
        "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
    ]
    let (_, _, exercises) = try parsedDay(cells, hidden: [15, 16])

    #expect(exercises[0].sets.map(\.state) == states)
}

/// Before the app read a drop row with no Sets count, a top Set whose Notes hold a Coach Note sent
/// its Set Log to that row. The log stays the top Set's, and the Drop takes the next free row.
@Test func aTopSetsLogOnAnUnreadDropRowStaysTheTopSets() throws {
    let cells = layout(["K15": "Brace hard", "F16": "8", "H16": "Drop 20%", "K16": "175x6@8"])
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises[0].sets.map(\.setLog) == [SetLog(weight: .pounds(175), reps: 6, rpe: .eight), nil])
    #expect(exercises[0].sets.map(\.prescribedLoad) == ["RPE8", "Drop 20%"])
    #expect(setLogRows(try #require(day.exerciseAnchors.first), sets: 2, snapshot: snapshot, day: day) == [15, 16])
}

@Test func threeTopSetLogsOnAnUnreadDropRowStayTheTopSets() throws {
    let cells = layout(
        ["D15": "3", "K15": "Brace", "F16": "", "H16": "Drop 20%", "K16": "185x6@8, 147.5x8@8, 147.5x8@8"]
    )
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises[0].sets.map(\.state) == [.logged, .logged, .logged, .pending])
    #expect(setLogRows(try #require(day.exerciseAnchors.first), sets: 4, snapshot: snapshot, day: day) == [15, 15, 15, 16])
}

@Test func aBareShareAfterADropTakesItsWord() throws {
    let (_, _, exercises) = try parsedDay(layout(dropLine, ["H16": "Drop 10%, 15%"]), hidden: [])

    #expect(exercises[0].sets.map(\.prescribedLoad) == ["RPE8", "Drop 10%", "Drop 15%"])
}

/// A named row is an Exercise of its own, as the app read it before it read Drop lines, whatever
/// its name and Load say. Its Set Logs, queued writes and Last Set RPE stay that Exercise's.
@Test(arguments: ["Drop", "↳", "HB SQ Drop", "Drop set", "Leg Press Drop Set"])
func aNamedDropRowIsAnExerciseOfItsOwn(name: String) throws {
    let cells = layout(["K15": "Brace hard", "C16": name, "D16": "1", "F16": "8", "H16": "Drop 20%", "K16": "147.5x8@8"])
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises.map(\.exerciseName.entered) == ["HB SQ", name, "Next Lift"])
    #expect(exercises[0].sets.map(\.setLog) == [nil])
    #expect(exercises[1].sets.map(\.setLog) == [SetLog(weight: .pounds(147.5), reps: 8, rpe: .eight)])
    #expect(setLogRows(day.exerciseAnchors[1], sets: 1, snapshot: snapshot, day: day) == [15])
}

/// A row the app gave a Set count before it read Drop lines keeps that count, its Sets cell's
/// leading number, so no Exercise gains Sets or moves its Set Logs. `x2` counts only on a Drop line.
@Test(
    arguments: [
        (layout(["D16": "x2", "F16": "8", "H16": "RPE7"]), 1),
        (layout(["D15": "x3"]), 1),
        (layout(["D15": "1+2"]), 1),
        (layout(["D15": "1+2", "F15": "6, 8", "H15": "RPE8, Drop 20%"]), 1),
        (layout(["D16": "1+2", "F16": "8", "H16": "RPE7", "D17": "2", "F17": "8", "H17": "RPE7"]), 4)
    ] as [([String: String], Int)]
)
func aRowTheAppCountedBeforeKeepsItsCount(cells: [String: String], setCount: Int) throws {
    let (_, _, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises[0].sets.count == setCount)
}

/// `layout` with the next Exercise on row 22, leaving rows 16 to 21 to the squat.
private func roomyLayout(_ cells: [String: String]) -> [String: String] {
    layout(["C18": "", "D18": "", "F18": "", "H18": "", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"], cells)
}

/// Each named Drop row keeps its own span, so a Coach Note in its Notes sends its log to the next
/// row of that span, as before the app read Drop lines. An unnamed Drop line above it stays within
/// the Exercise above.
@Test(
    arguments: [
        (
            roomyLayout(["K15": "175x6@8", "C17": "HB SQ Drop", "F17": "8", "H17": "Drop 20%", "K17": "Slow eccentric", "K18": "140x8@8"]),
            [["175x6@8"], ["140x8@8"], ["", ""]]
        ),
        (
            roomyLayout([
                "K15": "175x6@8", "C16": "Drop", "F16": "8", "H16": "Drop 20%", "K16": "Keep tight",
                "C17": "Drop", "F17": "8", "H17": "Drop 30%", "K17": "Fast", "K18": "122.5x8@8"
            ]),
            [["175x6@8"], [""], ["122.5x8@8"], ["", ""]]
        ),
        (
            roomyLayout([
                "K15": "Brace", "F16": "8", "H16": "Drop 20%", "K16": "175x6@8",
                "C17": "Drop", "F17": "8", "H17": "Drop 30%", "K17": "Fast", "K18": "122.5x8@8"
            ]),
            [["175x6@8", ""], ["122.5x8@8"], ["", ""]]
        )
    ] as [([String: String], [[String]])]
)
func aNamedDropRowsCoachNoteSendsItsLogToItsOwnNextRow(cells: [String: String], logs: [[String]]) throws {
    let (_, _, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises.map { $0.sets.map { $0.setLog?.formatted ?? "" } } == logs)
}

/// A Sets cell the app read no count in before, such as `100`, adds a Drop: the top Set's log the
/// app sent to that row stays the top Set's.
@Test func aDropRowsSetsCellPastTheLimitKeepsTheTopSetsLog() throws {
    let cells = roomyLayout(["K15": "Brace", "D16": "100", "F16": "8", "H16": "Drop 20%", "K16": "175x6@8"])
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises[0].sets.map(\.setLog) == [SetLog(weight: .pounds(175), reps: 6, rpe: .eight), nil])
    #expect(setLogRows(try #require(day.exerciseAnchors.first), sets: 2, snapshot: snapshot, day: day) == [15, 16])
}

/// Coach text on a spare row is never a Drop's Set Log.
@Test(
    arguments: [
        (roomyLayout(["K15": "175x6@8", "F16": "8", "H16": "Drop 20%", "K16": "Slow", "K17": "Keep chest up"]), [14, 17])
    ] as [([String: String], [Int?])]
)
func aDropLeavesALegacyLogAndCoachTextAlone(cells: [String: String], rows: [Int?]) throws {
    let (snapshot, day, exercises) = try parsedDay(cells, hidden: [])

    #expect(exercises[0].sets.dropFirst().allSatisfy { $0.state == .pending })
    #expect(setLogRows(try #require(day.exerciseAnchors.first), sets: rows.count, snapshot: snapshot, day: day) == rows)
}

#if OFFLINE_SHEET
    import Foundation

    /// Seed workbooks in the coach's canonical layout, fed through the real parser rather than built
    /// as a SwiftData graph, so a scenario proves the whole Sheet round trip.
    public enum WorkbookScenario: String, CaseIterable, Sendable {
        /// One Block tab, two logged-nothing Weeks, and an Unavailable Day 3 in Week 2 (a Partially
        /// Uploaded Block). The Coach Note on the RDL exercises the Visible Writable Row rule, and
        /// Bench Press carries one `%1RM` for every Set of its Line.
        case freshBlock = "fresh-block"
        /// The Block the app's UI fixture boots into when a launch names no scenario: four Weeks of
        /// four Days, eleven of them Unavailable Sessions with no prescription rows (a Partially
        /// Uploaded Block). It carries a `%1RM` per Set on the main lifts and a Drop Load on the RDL,
        /// so both of those Load Suggestion arms are reachable from cells a coach could have typed.
        /// The first Set of Back Squat and of Deadlift each sits on a Prescription Line whose Notes
        /// cell holds the Coach Note, so its Set Log flushes to the Exercise's spare row (#942).
        case partialUpload = "partial-upload"
        /// The Block the UI fixture boots into for the Full Block scenario: `partial-upload`'s Week 1
        /// Days 1 and 2, a Deadlift on Week 1 Day 3, and an Accessory on every other Day, so all
        /// sixteen Sessions are Available Sessions.
        case fullBlock = "full-block"
        /// Week 1 Day 1's Back Squat and RDL with nothing logged, the Current Session a test of the
        /// Stage starts from.
        case currentSessionWithPendingSets = "current-session-with-pending-sets"
        /// Week 1 Day 1 alone, its Back Squat's first Set logged and its second open.
        case partiallyLoggedSession = "partially-logged-session"
        /// Three Days of Week 1, each one main lift with its first Set logged and its second open,
        /// so every Session has Open Exercises.
        case openExercises = "open-exercises"
        /// `open-exercises` with Day 2 a one-Set Bench Press, logged, so the Current Session is
        /// complete while Day 1's Back Squat is still open.
        case completedOpenExercises = "completed-open-exercises"
        /// One Session of eight one-Set Exercises, the first logged, long enough to scroll.
        case longSession = "long-session"
        /// A Back Squat with one Set logged and one skipped on Day 1, a Perfect Session, and an
        /// Unavailable Day 2 to move on to.
        case perfectMoveOnCelebration = "perfect-move-on-celebration"
        /// One Session of every status Block Overview draws: a complete Day 1, Day 2 with Open
        /// Exercises, Day 3 to train next, and Week 2 Day 1 still upcoming.
        case blockOverviewWithMixedSessionStates = "block-overview-with-mixed-session-states"
        /// The longest and oddest cells a coach realistically types, for finding where the UI breaks:
        /// a Cadence-prefixed mega-name with a paragraph Coach Note and a text Load, a four-digit
        /// Set Log beside an Unstructured one, a two-Line row with a range and a timed Reps cell, a
        /// three-letter name, and twelve one-rep Sets. Every other Session of its four Weeks holds
        /// one long-named Exercise.
        case worstCase = "worst-case"

        static let spreadsheetId = "FIXTURE"
        static let title = "Fixture Training Log"
        static let blockTab = "Block 27"
    }

    extension WorkbookScenario {
        private static let roleHeaderOffsets: [(offset: Int, label: String)] = [
            (1, "Sets"), (3, "Reps"), (4, "%1RM"), (5, "Load"), (6, "Last set RPE"), (8, "Notes")
        ]

        static let dayStartColumns = [2, 18, 34, 50]

        /// Rows between one Week's `Day N` header row and the next, as `fresh-block` lays them out.
        private static let weekRowStride = 25

        /// One Week per entry of `daysPerWeek`, each with that many Days, under Training Max
        /// 315/225/405, with `prescriptions` written into them. A Day no prescription lands in is an
        /// Unavailable Session.
        static func block(daysPerWeek: [Int], prescriptions: [[String: String]]) -> LocalWorkbook {
            var cells: [String: String] = [
                "E6": "Training Max",
                "C7": "Squat", "E7": "315",
                "C8": "Bench Press", "E8": "225",
                "C9": "Deadlift", "E9": "405"
            ]
            let headers = daysPerWeek.enumerated().map { weekHeaders(week: $0.offset + 1, days: $0.element) }
            for part in headers + prescriptions {
                cells.merge(part) { _, new in new }
            }
            return LocalWorkbook(
                spreadsheetId: spreadsheetId,
                title: title,
                tabs: [blockTab: LocalWorkbook.Tab(rows: 110, cols: 60, cells: cells)]
            )
        }

        /// Week `week`'s `Day 1` to `Day <days>` headers, their date cells, and their role headers.
        /// A Day with no prescription rows under its headers is an Unavailable Session.
        private static func weekHeaders(week: Int, days: Int) -> [String: String] {
            let headerRow = headerRow(week: week)
            var cells: [String: String] = [:]
            for (index, start) in dayStartColumns.prefix(days).enumerated() {
                cells["\(columnName(start))\(headerRow)"] = "Day \(index + 1)"
                cells["\(columnName(start))\(headerRow + 1)"] = strideDate(week: week, day: index + 1)
                cells.merge(roleHeaders(row: headerRow + 2, dayStart: start)) { _, new in new }
            }
            return cells
        }

        private static func headerRow(week: Int) -> Int {
            12 + (week - 1) * weekRowStride
        }

        /// The row of a Day's first prescription: under its `Day N`, date, and role header rows.
        static func firstPrescriptionRow(of address: SessionAddress) -> Int {
            headerRow(week: address.week) + 3
        }

        static func merged(_ parts: [[String: String]]) -> [String: String] {
            parts.reduce(into: [:]) { cells, part in cells.merge(part) { _, new in new } }
        }

        /// The Session's calendar day on a 7-day stride from 1 January 2001, the reference date, so
        /// Day `d` of Week `w` falls on day `(w - 1) * 7 + d` after it.
        private static func strideDate(week: Int, day: Int) -> String {
            "1/\(1 + (week - 1) * 7 + day)/2001"
        }

        static func roleHeaders(row: Int, dayStart: Int) -> [String: String] {
            Dictionary(uniqueKeysWithValues: roleHeaderOffsets.map { ("\(columnName(dayStart + $0.offset))\(row)", $0.label) })
        }

        // One parameter per spreadsheet column the prescription writes. A struct here would carry
        // the same values one call further out and name the columns twice. A nil name is a
        // continuation row: another Prescription Line of the Exercise above it (ADR-0010).
        // swiftlint:disable:next function_parameter_count
        static func prescription(
            row: Int,
            dayStart: Int,
            name: String?,
            sets: Int,
            reps: String,
            percentOneRM: String? = nil,
            load: String,
            notes: String? = nil
        ) -> [String: String] {
            var cells = [
                "\(columnName(dayStart + 1))\(row)": String(sets),
                "\(columnName(dayStart + 3))\(row)": reps,
                "\(columnName(dayStart + 5))\(row)": load
            ]
            if let name {
                cells["\(columnName(dayStart))\(row)"] = name
            }
            if let percentOneRM {
                cells["\(columnName(dayStart + 4))\(row)"] = percentOneRM
            }
            if let notes {
                cells["\(columnName(dayStart + 8))\(row)"] = notes
            }
            return cells
        }
    }

    extension WorkbookScenario {
        /// The scenario's Block tab as a sync reads it: `SheetParser.parse`, the first of the two
        /// calls `SyncCoordinator.sync` makes. Every scenario has the one tab.
        func parsedBlockTab() -> ParsedBlock {
            guard let tab = workbook().tabs[Self.blockTab] else {
                preconditionFailure("\(rawValue) has no \(Self.blockTab) tab")
            }
            return SheetParser().parse(snapshot: tab.snapshot, tabName: Self.blockTab)
        }

        /// The Block a sync of this scenario would persist: the parse, then `BlockBuilder.makeBlock`,
        /// the second call. It stops before the overlays `SyncCoordinator.replacePersistedBlock`
        /// applies, which only matter once local athlete state exists.
        @MainActor
        func block() -> Block {
            BlockBuilder.makeBlock(from: parsedBlockTab().block)
        }
    }
#endif

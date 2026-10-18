import Foundation

/// An Exercise History entry's identity, an Exercise's full name in one Session (ADR-0012).
struct LastPerformedEntryKey: Hashable, Sendable {
    let fullName: String
    /// The performed-in Session as a `SessionCoordinate.storageValue`.
    let source: String
}

enum LastPerformedExtractor {
    /// Every (Exercise, Session) in the block that earns no entry, with every cell its rows hold.
    /// Two same-named Exercises in one Session share a key (#813), so their cells pool. A sync
    /// retracts the key's entry only when none of the cells holds the entry's result (#812).
    static func sheetCellsByKeyWithoutEntry(from block: ParsedBlockModel) -> [LastPerformedEntryKey: [String]] {
        var cellsByKey: [LastPerformedEntryKey: [String]] = [:]
        forEachExercise(in: block) { exercise, _, source in
            let key = LastPerformedEntryKey(fullName: exercise.exerciseName.entered, source: source)
            cellsByKey[key, default: []] += exercise.sheetCells
        }
        for occurrence in occurrences(from: block) {
            cellsByKey[occurrence.key] = nil
        }
        return cellsByKey
    }

    /// Whether the cells of an Exercise's rows still hold an entry's result. Each token of the result
    /// is found by its numbers in order, so `315x5@7` is held by `315X5@7`, `315lbx5@7`,
    /// `315 x 5 @ 7.0` and `315x5@7 felt heavy` alike, and a Legacy Log's `60x7@9.5` the same way.
    /// A token with no numbers, an Unstructured Set Log such as `heavy`, is found as case-folded
    /// text. A `skip` is no result and never counts. A result reformatted until its numbers cannot
    /// be read, or a cell whose numbers changed, is not found, and the entry goes.
    static func sheetCells(_ cells: [String], hold resultText: String) -> Bool {
        let tokens = splitSheetNotesList(resultText).filter {
            !$0.isEmpty && $0.caseInsensitiveCompare(SetLogToken.skipSentinel) != .orderedSame
        }
        return tokens.contains { token in
            let tokenNumbers = numbers(in: token)
            return cells.contains { cell in
                tokenNumbers.isEmpty
                    ? cell.range(of: token, options: .caseInsensitive) != nil
                    : numbers(in: cell).containsRun(tokenNumbers)
            }
        }
    }

    private static func numbers(in text: String) -> [Double] {
        text.matches(of: /\d+(?:\.\d+)?/).compactMap { Double($0.output) }
    }

    static func entries(from block: ParsedBlockModel) -> [LastPerformedEntry] {
        occurrences(from: block).map(LastPerformedEntry.init)
    }

    /// Every evidence-bearing (Exercise, Session) occurrence in the block, one canonical value each.
    ///
    /// Append-only (ADR-0012): unlike the former single-entry index, this does not collapse
    /// to the latest occurrence per name. Each Session an Exercise was performed in yields its
    /// own occurrence, keyed downstream by (Entered Name, `source`). Occurrences are emitted in
    /// Session order (week → day → Exercise), each carrying its already-derived display text.
    static func occurrences(from block: ParsedBlockModel) -> [LastPerformedOccurrence] {
        var occurrences: [LastPerformedOccurrence] = []
        forEachExercise(in: block) { exercise, session, source in
            guard let resultText = displayText(for: exercise) else { return }

            occurrences.append(
                LastPerformedOccurrence(
                    exerciseName: exercise.exerciseName,
                    resultText: resultText,
                    performedOn: session.date ?? .distantPast,
                    source: source
                )
            )
        }
        return occurrences
    }

    /// Visits every Exercise in Session order (week → day → Exercise) with its Session's `source`.
    private static func forEachExercise(
        in block: ParsedBlockModel,
        _ body: (ParsedExercise, ParsedSession, String) -> Void
    ) {
        for week in block.weeks {
            for session in week.days {
                let source = SessionCoordinate(blockTab: block.tabName, address: week.address(of: session)).storageValue
                for exercise in session.exercises {
                    body(exercise, session, source)
                }
            }
        }
    }

    /// The Last Performed display text for one Exercise as logged in a Session (ADR-0012), or nil
    /// when the occurrence earns no entry.
    private static func displayText(for exercise: ParsedExercise) -> String? {
        let evidence = exercise.setLevelCompletionEvidence
        if let resultText = evidence.resultText { return resultText }
        if evidence.contains(.skipped) { return nil }
        return exercise.legacyLogAsCompletionEvidence
    }
}

extension [Double] {
    /// Whether `run` appears as a contiguous slice, in order.
    fileprivate func containsRun(_ run: [Double]) -> Bool {
        guard !run.isEmpty, run.count <= count else { return false }
        return (0...(count - run.count)).contains { self[$0..<$0 + run.count].elementsEqual(run) }
    }
}

import Foundation
import SwiftData

/// One `exercise_history` entry — an Exercise as logged in a single past Session.
///
/// The store is append-only (ADR-0012): dedup is app-level on (`fullName`, `source`),
/// so `fullName` is intentionally **not** unique — the same Exercise keeps a distinct
/// entry per Session it was performed in. Last Performed is the most-recent-entry query
/// over these rows.
///
/// Completion evidence is stored as a single derived `resultText` (PRD #330): the display text is
/// assembled once at extract time, so the row is a straight persistence of `LastPerformedOccurrence`
/// with no read-time reconciliation of a typed result against free text.
///
/// `resultText` carries a default so this collapse stays a lightweight migration: earlier builds
/// persisted a typed `result: SetLog?` alongside an optional `resultText`, so a device upgrading with
/// existing rows may hold `resultText == nil`. The app opens its store with `try!` and no
/// `MigrationPlan`, and making a previously-optional attribute required *without* a default is not a
/// lightweight change — it would fail container init and crash on launch. The default lets SwiftData
/// backfill those rows; this is a rebuildable cache (ADR-0002), so any blanked row is re-derived on
/// the next sync.
@Model
final class LastPerformedEntry {
    var fullName: String
    var baseName: String
    var resultText: String = ""
    var performedOn: Date
    var source: String

    init(fullName: String, baseName: String, resultText: String, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.resultText = resultText
        self.performedOn = performedOn
        self.source = source
    }

    /// Convenience for the live-logging path, where evidence is a lone structured Set Log: its
    /// display text is `SetLog.formatted`, derived here so callers never hold the dual shape.
    convenience init(fullName: String, baseName: String, result: SetLog, performedOn: Date, source: String) {
        self.init(
            fullName: fullName,
            baseName: baseName,
            resultText: result.formatted,
            performedOn: performedOn,
            source: source
        )
    }

    convenience init(_ occurrence: LastPerformedOccurrence) {
        self.init(
            fullName: occurrence.fullName,
            baseName: occurrence.baseName,
            resultText: occurrence.resultText,
            performedOn: occurrence.performedOn,
            source: occurrence.source
        )
    }

    var occurrence: LastPerformedOccurrence {
        LastPerformedOccurrence(
            fullName: fullName,
            baseName: baseName,
            resultText: resultText,
            performedOn: performedOn,
            source: source
        )
    }
}

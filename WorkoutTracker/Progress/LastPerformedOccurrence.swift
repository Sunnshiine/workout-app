import Foundation

/// One Last Performed occurrence — an Exercise as logged in a single past Session (ADR-0012).
///
/// The canonical, `Sendable` completion-evidence shape (PRD #330): a full name, its
/// Cadence-stripped base name, one already-derived display text, the performed-on date, and a
/// source label. The display text is derived exactly once — by the extractor when it assembles
/// the Set-ordered tokens (or the Legacy Log) — so there is no second read-time reconciliation of
/// a typed result against free text. The persisted `LastPerformedEntry` initializes from and
/// projects back to this type, which is also what the off-main-actor backfill scan carries.
struct LastPerformedOccurrence: Sendable, Equatable {
    var fullName: String
    var baseName: String
    var resultText: String
    var performedOn: Date
    var source: String
}

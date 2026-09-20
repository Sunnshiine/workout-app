import Foundation

/// One Last Performed occurrence — an Exercise as logged in a single past Session (ADR-0012).
///
/// The canonical, `Sendable` completion-evidence shape (PRD #330): a full name, its
/// Cadence-stripped base name, one already-derived display text, the performed-on date, and a
/// source label. The display text is derived exactly once — by the extractor when it assembles
/// the Set-ordered tokens (or the Legacy Log) — so there is no second read-time reconciliation of
/// a typed result against free text. The persisted `LastPerformedEntry` initializes from and
/// projects back to this type, which is also what the Exercise History fill's off-main-actor scan
/// carries.
struct LastPerformedOccurrence: Sendable, Equatable {
    let fullName: String
    let baseName: String
    let resultText: String
    let performedOn: Date
    /// The performed-in Session as a `SessionCoordinate.storageValue`, and the ADR-0012 dedup key.
    let source: String
}

import Foundation
import SwiftData

/// One `exercise_history` entry — an Exercise as logged in a single past Session.
///
/// The store is append-only (ADR-0012): dedup is app-level on (`fullName`, `source`),
/// so `fullName` is intentionally **not** unique — the same Exercise keeps a distinct
/// entry per Session it was performed in. Last Performed is the most-recent-entry query
/// over these rows.
@Model
final class LastPerformedEntry {
    var fullName: String
    var baseName: String
    var result: SetLog?
    var resultText: String?
    var performedOn: Date
    var source: String

    var displayResultText: String {
        resultText ?? result?.formatted ?? ""
    }

    init(fullName: String, baseName: String, result: SetLog, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.result = result
        self.resultText = nil
        self.performedOn = performedOn
        self.source = source
    }

    init(fullName: String, baseName: String, resultText: String, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.result = nil
        self.resultText = resultText
        self.performedOn = performedOn
        self.source = source
    }
}

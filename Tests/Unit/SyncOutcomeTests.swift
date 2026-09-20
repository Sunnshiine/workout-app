import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Suite("SyncOutcome")
struct SyncOutcomeTests {
    /// The wire contract. Every name and every key here is what an agent parses, so a change to
    /// one of these strings is a change to the CLI's output.
    @Test func everyOutcomeEncodesUnderItsOwnStatusSoAFailedWriteNeverReadsLikeAParserWarning() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let encodings: [(SyncOutcome, String)] = [
            (.clear, #"{"messages":[],"status":"clear"}"#),
            (
                .localWriteFailed("the local store is full"),
                #"{"messages":["the local store is full"],"status":"localWriteFailed"}"#
            ),
            (.sheetUnreachable, #"{"messages":[],"status":"sheetUnreachable"}"#),
            (.writesQueued(2), #"{"count":2,"messages":[],"status":"writesQueued"}"#),
            (
                .writesRefused(["Squat: Expected '', found 'coach edited'"]),
                #"{"messages":["Squat: Expected '', found 'coach edited'"],"status":"writesRefused"}"#
            ),
            (.noBlockTab, #"{"messages":[],"status":"noBlockTab"}"#),
            (
                .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]),
                #"{"messages":["Parse warning: no week sections (no 'Day N' headers) in Block 27"],"status":"parseWarnings"}"#
            ),
            (
                .historyFillFailed("the index is full"),
                #"{"messages":["the index is full"],"status":"historyFillFailed"}"#
            )
        ]

        for (outcome, expected) in encodings {
            let encoded = try encoder.encode(SyncOutcomeSnapshot(outcome))
            #expect(String(bytes: encoded, encoding: .utf8) == expected, "\(outcome) encoded wrong")
        }
    }

    @Test func theSyncVerdictFollowsTheReadExceptWhereARefusedWriteSurvivesIt() {
        let refused = SyncOutcome.writesRefused(["Squat: Expected '', found 'coach edited'"])
        let warnings = SyncOutcome.parseWarnings(["Parse warning: no week sections"])

        #expect(SyncOutcome.sync(sheetRead: warnings, flush: refused) == refused)
        #expect(SyncOutcome.sync(sheetRead: .clear, flush: refused) == refused)
        #expect(SyncOutcome.sync(sheetRead: .noBlockTab, flush: refused) == .noBlockTab)
        #expect(SyncOutcome.sync(sheetRead: .sheetUnreachable, flush: refused) == .sheetUnreachable)

        #expect(SyncOutcome.sync(sheetRead: .clear, flush: .writesQueued(1)) == .clear)
        #expect(SyncOutcome.sync(sheetRead: warnings, flush: .writesQueued(1)) == warnings)
        #expect(SyncOutcome.sync(sheetRead: .clear, flush: .clear) == .clear)
    }
}

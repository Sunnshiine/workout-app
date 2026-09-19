import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Suite("SyncCoordinator.State projection")
struct SyncStateProjectionTests {

    @Test func everyOutcomeProjectsToTheStateTheCLIAlreadyPrinted() {
        let projections: [(SyncOutcome, SyncCoordinator.State)] = [
            (.clear, .idle),
            (.sheetUnreachable, .offline),
            (.writesQueued(3), .pendingWrites(3)),
            (.localWriteFailed("the local store is full"), .conflict(["Local write failed: the local store is full"])),
            (
                .writesRefused(["Squat: Expected '', found 'coach edited'"]),
                .conflict(["Squat: Expected '', found 'coach edited'"])
            ),
            (.noBlockTab, .conflict(["No block tab found in the spreadsheet"])),
            (
                .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]),
                .conflict(["Parse warning: no week sections (no 'Day N' headers) in Block 27"])
            ),
            (
                .historyFillFailed("the index is full"),
                .conflict(["Exercise History fill failed: the index is full"])
            )
        ]

        for (outcome, expected) in projections {
            #expect(SyncCoordinator.State(outcome) == expected, "\(outcome) projected wrong")
        }
    }

    /// Over the wire the five still read alike. That is the collapse #590 removes; a reader of
    /// this file should not mistake it for the athlete's view.
    @Test func theFiveOutcomesThatWantTheAthleteAreStillIndistinguishableOverTheWire() {
        let conflicts: [SyncOutcome] = [
            .localWriteFailed("x"), .writesRefused(["x"]), .noBlockTab, .parseWarnings(["x"]), .historyFillFailed("x")
        ]
        for outcome in conflicts {
            #expect(SyncStateSnapshot(SyncCoordinator.State(outcome)).status == "conflict")
        }
    }

    @Test func theEncodedShapeCarriesTheStatusAndTheMessages() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let refused = SyncStateSnapshot(SyncCoordinator.State(.writesRefused(["Squat: Expected '', found 'coach edited'"])))
        #expect(
            String(decoding: try encoder.encode(refused), as: UTF8.self)
                == #"{"messages":["Squat: Expected '', found 'coach edited'"],"status":"conflict"}"#
        )

        let queued = SyncStateSnapshot(SyncCoordinator.State(.writesQueued(2)))
        #expect(String(decoding: try encoder.encode(queued), as: UTF8.self) == #"{"count":2,"status":"pendingWrites"}"#)

        let clear = SyncStateSnapshot(SyncCoordinator.State(.clear))
        #expect(String(decoding: try encoder.encode(clear), as: UTF8.self) == #"{"status":"idle"}"#)
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

import Foundation
import Testing

@testable import WorkoutTracker

// Pins the Block each UI launch scenario boots into against the bare parse of its workbook. Until
// #571 the fixture's Blocks were graphs built by hand in `Fixtures/WorkoutFixtureScenarios.swift`,
// and nothing compared them with cells the real parser reads, so a disagreement reached the Visual
// gate (ADR-0007) and was recorded there as intended appearance. Each slice of #571 paired one
// scenario's graph with a workbook, recorded what the cells could not express, then seeded the
// scenario from the workbook and deleted the graph; #970 deleted the last. The seeded side is the
// Block `UITestFixture.boot` leaves in a fresh application's store, so each row now pins that the
// scenario seeds that workbook and no other, and that only `unwritableSetLogs` lie over it.
//
// Pairing is by structural address and nothing else: the Block, then Week number, then Day
// number, then `Exercise.order`, then `ExerciseSet.index`. A name is compared data, never a
// pairing key, so "Pull-Up" and "BW Pull Up" at the same address pair and then disagree instead of
// failing to pair. An address present on only one side is reported once and not descended into,
// because every address beneath an absent address is absent too.
//
// `recordedDrift` holds every disagreement that exists today, with the side that is wrong named
// per entry. It is asserted in both directions, so an unrecorded disagreement fails and a
// recorded one that stops happening fails as stale and the list can only shrink as the
// per-scenario migrations behind #571 land. No entry is a tolerance: each names one field at one
// address with both literal values.
//
// Reach: since #970 pairs the scenarios that hold athlete state, `state` and `setLog` are
// exercised, including Skipped Sets read from the `skip` sentinel. `unstructuredSetLog`, `loggedAt`
// and `legacyLog` are still empty on both sides of every pair.

// MARK: - The difference

private enum Drift: Hashable, CustomStringConvertible {
    case onlyInSeeded(String)
    case onlyInParsed(String)
    case field(_ address: String, _ name: String, seeded: String?, parsed: String?)

    var description: String {
        switch self {
        case .onlyInSeeded(let address):
            "\(address) — only in the seeded Block"
        case .onlyInParsed(let address):
            "\(address) — only in the workbook's parse"
        case .field(let address, let name, let seeded, let parsed):
            "\(address).\(name) — seeded \(quoted(seeded)) vs parsed \(quoted(parsed))"
        }
    }
}

private func quoted(_ value: String?) -> String {
    value.map { "\"\($0)\"" } ?? "none"
}

private func text(_ date: Date?) -> String? {
    date.map { $0.ISO8601Format() }
}

private func text(_ number: Double?) -> String? {
    number.map { Weight.pounds($0).label }
}

// MARK: - The walk

/// One accumulation path for the whole walk, so the reported list reads down the Block in address
/// order the way the app does.
@MainActor
private final class DriftLog {
    private(set) var drift: [Drift] = []

    func note(_ difference: Drift) {
        drift.append(difference)
    }

    func compare(_ address: String, _ name: String, _ seeded: String?, _ parsed: String?) {
        guard seeded != parsed else { return }
        drift.append(.field(address, name, seeded: seeded, parsed: parsed))
    }
}

@MainActor
private func drift(seeded: Block, parsed: Block) -> [Drift] {
    let log = DriftLog()
    log.compare("block", "tabName", seeded.tabName, parsed.tabName)
    let seededMaxes = seeded.trainingMaxes
    let parsedMaxes = parsed.trainingMaxes
    for lift in MainLift.allCases {
        log.compare("block", "trainingMax.\(lift)", text(seededMaxes[lift]), text(parsedMaxes[lift]))
    }

    let seededSessions = sessionsByAddress(seeded)
    let parsedSessions = sessionsByAddress(parsed)
    let sessions = Set(seededSessions.keys).union(parsedSessions.keys)
    for address in sessions.sorted(by: { ($0.week, $0.day) < ($1.week, $1.day) }) {
        guard let seededSession = seededSessions[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedSession = parsedSessions[address] else {
            log.note(.onlyInSeeded(address.description))
            continue
        }
        // `Session.date` is deliberately not walked. A workbook authors a calendar day that
        // `SheetParser.parseDate` resolves in the machine's time zone, so a recorded instant
        // passes in EDT and fails on a UTC runner. The dates are pinned instead,
        // machine-independently, by `theSeededFourWeekDatesAreTheirWorkbooksDateCells`.
        noteExerciseDrift(seeded: seededSession, parsed: parsedSession, at: address, into: log)
    }
    return log.drift
}

@MainActor
private func noteExerciseDrift(seeded: Session, parsed: Session, at session: SessionAddress, into log: DriftLog) {
    let seededExercises = exercisesByAddress(seeded, in: session)
    let parsedExercises = exercisesByAddress(parsed, in: session)
    for address in Set(seededExercises.keys).union(parsedExercises.keys).sorted(by: { $0.order < $1.order }) {
        guard let seededExercise = seededExercises[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedExercise = parsedExercises[address] else {
            log.note(.onlyInSeeded(address.description))
            continue
        }
        let id = address.description
        log.compare(id, "name", seededExercise.name, parsedExercise.name)
        log.compare(id, "baseName", seededExercise.baseName, parsedExercise.baseName)
        log.compare(id, "cadence", seededExercise.cadence, parsedExercise.cadence)
        log.compare(id, "coachNote", seededExercise.coachNote, parsedExercise.coachNote)
        log.compare(id, "legacyLog", seededExercise.legacyLog, parsedExercise.legacyLog)
        noteSetDrift(seeded: seededExercise, parsed: parsedExercise, at: address, into: log)
    }
}

@MainActor
private func noteSetDrift(seeded: Exercise, parsed: Exercise, at exercise: ExerciseAddress, into log: DriftLog) {
    let seededSets = setsByAddress(seeded, in: exercise)
    let parsedSets = setsByAddress(parsed, in: exercise)
    for address in Set(seededSets.keys).union(parsedSets.keys).sorted(by: { $0.index < $1.index }) {
        guard let seededSet = seededSets[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedSet = parsedSets[address] else {
            log.note(.onlyInSeeded(address.description))
            continue
        }
        let id = address.description
        log.compare(id, "state", seededSet.state.rawValue, parsedSet.state.rawValue)
        log.compare(id, "prescribedReps", seededSet.prescribedReps, parsedSet.prescribedReps)
        log.compare(id, "prescribedLoad", seededSet.prescribedLoad, parsedSet.prescribedLoad)
        log.compare(id, "percentOneRM", seededSet.percentOneRM, parsedSet.percentOneRM)
        log.compare(id, "setLog", seededSet.setLog?.formatted, parsedSet.setLog?.formatted)
        log.compare(id, "unstructuredSetLog", seededSet.unstructuredSetLog, parsedSet.unstructuredSetLog)
        log.compare(id, "loggedAt", text(seededSet.loggedAt), text(parsedSet.loggedAt))
    }
}

/// Traps on a repeated address rather than dropping one side of it, as the Exercise and Set maps
/// below do: two Day 2s in one Week is a malformed fixture, not a difference to report.
@MainActor
private func sessionsByAddress(_ block: Block) -> [SessionAddress: Session] {
    Dictionary(
        uniqueKeysWithValues: block.weeks.flatMap { week in
            week.sessions.map { (week.address(of: $0), $0) }
        }
    )
}

@MainActor
private func exercisesByAddress(_ session: Session, in address: SessionAddress) -> [ExerciseAddress: Exercise] {
    Dictionary(
        uniqueKeysWithValues: session.exercises.map { (ExerciseAddress(session: address, order: $0.order), $0) }
    )
}

@MainActor
private func setsByAddress(_ exercise: Exercise, in address: ExerciseAddress) -> [SetAddress: ExerciseSet] {
    Dictionary(uniqueKeysWithValues: exercise.sets.map { (SetAddress(exercise: address, index: $0.index), $0) })
}

/// The parse and build a sync makes, so the comparison runs against the real interpretation rather
/// than a second one written here. It leaves out `WorkbookScenario.unwritableSetLogs`, which no cell
/// holds, so each of those shows as recorded drift until #942 gives it a cell. It stops where
/// `SyncCoordinator.replacePersistedBlock` begins: the overlays that follow, which re-apply pending
/// writes and preserve local `loggedAt`, are outside the harness and would matter the moment a
/// scenario holding athlete state is paired.
@MainActor
private func parsedBlock(_ scenario: WorkbookScenario) -> Block {
    // One tab, so "the Block tab" needs no selection rule here. A scenario that gains the
    // historical tabs Exercise History fills from has to say which tab it is pinning.
    #expect(scenario.workbook().tabs.count == 1, "\(scenario.rawValue) has more than one tab")
    #expect(scenario.parsedBlockTab().warnings == [], "\(scenario.rawValue) must parse cleanly before it can be compared")
    return BlockBuilder.makeBlock(from: scenario.parsedBlockTab().block)
}

// MARK: - The declared pairs

/// A `WorkbookScenario` and the launch scenario that fills the same fixture role. The workbook is
/// authored to reproduce what the scenario renders, so the two describe one workout.
private struct PairedScenario: Sendable, CustomStringConvertible {
    let workbook: WorkbookScenario
    let launch: UITestLaunch.Scenario

    var description: String { workbook.rawValue }
}

private let pairedScenarios: [PairedScenario] = [
    PairedScenario(workbook: .partialUpload, launch: .partialUpload),
    PairedScenario(workbook: .fullBlock, launch: .fullBlock),
    PairedScenario(workbook: .openExercises, launch: .openExercises),
    PairedScenario(workbook: .completedOpenExercises, launch: .completedOpenExercises),
    PairedScenario(workbook: .longSession, launch: .longSession),
    PairedScenario(workbook: .perfectMoveOnCelebration, launch: .perfectMoveOnCelebration)
]

/// Workbooks only `Tests/Support/WorkoutScenarios.swift` reads, so no launch boots them. #970
/// paired each with the hand-built graph it replaced, with no drift beyond `unwritableSetLogs`.
private let supportWorkbooks: [WorkbookScenario] = [
    .currentSessionWithPendingSets, .partiallyLoggedSession, .blockOverviewWithMixedSessionStates
]

/// Workbooks no launch scenario seeds from. `fresh-block` is the CLI's default scenario
/// (`Sources/WorkoutCLI/Commands/InitCommand.swift`), and its shape is pinned by
/// `Tests/Unit/WorkbookScenarioTests.swift`, `Sources/WorkoutCLI/README.md`,
/// `scripts/viewed-session-across-sync.sh`, and the verify skill's `cli-headless.md`, not by a graph.
private let workbooksWithoutALaunchScenario = Set<WorkbookScenario>([.freshBlock]).union(supportWorkbooks)

/// Every difference between the two sides today, in address order, with the side that is wrong
/// named per entry.
private let recordedDrift: [WorkbookScenario: [Drift]] = [
    // Seeded from its own workbook (#928), so nothing can drift. The two Accessory names were the
    // last entries: the hand-built graph named each Accessory after its Session while asserting
    // the base name "Accessory", a pair no name cell yields, and the workbook authors the name the
    // Stage renders.
    .partialUpload: [],
    // Seeded from its own workbook (#968). Its last entries were thirteen Accessory names, dropped
    // for the reason `partial-upload`'s two were.
    .fullBlock: [],
    // Seeded from their own workbooks (#970). The drift left is the first Set of each two-Line
    // lift, Logged at boot but Pending in the parse: its Line's Notes cell holds the Coach Note, so
    // no cell can hold the log until #942, and `unwritableSetLogs` logs it over the parse instead.
    .openExercises: firstSetLogged("w1d1", "235x5@6") + firstSetLogged("w1d2", "155x5@6") + firstSetLogged("w1d3", "305x3@6"),
    .completedOpenExercises: firstSetLogged("w1d1", "235x5@6"),
    .longSession: [],
    .perfectMoveOnCelebration: []
]

/// The two fields an unwritable Set Log drifts in: the first Set of the Session's first Exercise.
private func firstSetLogged(_ session: String, _ log: String) -> [Drift] {
    [
        .field("\(session).e0.s0", "state", seeded: "logged", parsed: "pending"),
        .field("\(session).e0.s0", "setLog", seeded: log, parsed: nil)
    ]
}

// MARK: - The gate

@MainActor
@Test(arguments: pairedScenarios)
private func aPairedScenarioDriftsOnlyWhereRecorded(pair: PairedScenario) async throws {
    let booted = try await BootedFixture.boot(pair.launch)
    let actual = drift(seeded: try booted.block(), parsed: parsedBlock(pair.workbook))
    let expected = try #require(recordedDrift[pair.workbook])

    let unrecorded = actual.filter { !expected.contains($0) }
    let stale = expected.filter { !actual.contains($0) }

    #expect(unrecorded.isEmpty, "\(pair) drifts in ways nothing records:\n\(list(unrecorded))")
    #expect(stale.isEmpty, "\(pair) no longer drifts here, so delete these entries:\n\(list(stale))")
}

/// The one field the walk does not compare, pinned here instead.
///
/// The workbook authors a calendar day and `SheetParser.parseDate` resolves it as local midnight,
/// so a recorded instant would read EDT on this machine and something else on a UTC runner. Each
/// seeded Session's local calendar day must be its date cell, which holds in every zone. The cells
/// keep the hand-built graphs' 7-day stride from the reference date, so under `TZ=UTC` the seeded
/// instants are the ones the graphs used to hand over. Both four-Week scenarios share the cells.
@MainActor
@Test(arguments: [UITestLaunch.Scenario.partialUpload, .fullBlock])
func theSeededFourWeekDatesAreTheirWorkbooksDateCells(scenario: UITestLaunch.Scenario) async throws {
    let booted = try await BootedFixture.boot(scenario)
    let seeded = sessionsByAddress(try booted.block())
    // Keyed by address and checked for coverage below, because the walk does not compare `date`:
    // this table is the only thing watching it, so a newly added Session must not slip past.
    let expected: [String: String] = [
        "w1d1": "1/2/2001", "w1d2": "1/3/2001", "w1d3": "1/4/2001", "w1d4": "1/5/2001",
        "w2d1": "1/9/2001", "w2d2": "1/10/2001", "w2d3": "1/11/2001", "w2d4": "1/12/2001",
        "w3d1": "1/16/2001", "w3d2": "1/17/2001", "w3d3": "1/18/2001", "w3d4": "1/19/2001",
        "w4d1": "1/23/2001", "w4d2": "1/24/2001", "w4d3": "1/25/2001", "w4d4": "1/26/2001"
    ]
    let localDay = DateFormatter()
    localDay.dateFormat = "M/d/yyyy"
    localDay.locale = Locale(identifier: "en_US_POSIX")

    #expect(Set(expected.keys) == Set(seeded.keys.map(\.description)), "a seeded Session has no pinned date")
    for (address, session) in seeded {
        let date = try #require(session.date, "\(address) has no date")
        #expect(localDay.string(from: date) == expected[address.description], "\(address) is not its date cell")
    }
}

@Test func everyScenarioIsPairedAndEveryWorkbookAccountedFor() {
    let paired = Set(pairedScenarios.map(\.launch))
    let pairedWorkbooks = Set(pairedScenarios.map(\.workbook))
    #expect(pairedWorkbooks.isDisjoint(with: workbooksWithoutALaunchScenario))
    #expect(pairedWorkbooks.union(workbooksWithoutALaunchScenario) == Set(WorkbookScenario.allCases))
    #expect(Set(recordedDrift.keys) == pairedWorkbooks)
    #expect(paired == Set(UITestLaunch.Scenario.allCases))
}

private func list(_ drift: [Drift]) -> String {
    drift.map { "  \($0)" }.joined(separator: "\n")
}

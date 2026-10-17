import Foundation
import Testing

@testable import WorkoutTracker

// Pins a hand-built fixture Block graph against the parse of the workbook paired with it.
// `Fixtures/WorkoutFixtureScenarios.swift` authors a Block graph by hand while
// `Fixtures/WorkbookScenarios.swift` authors cells the real parser reads, and until this file
// nothing compared the two — so a disagreement reached the Visual gate (ADR-0007) and was
// recorded there as intended appearance. Slice 1 of #571 built the harness; each later slice
// pairs one launch scenario with a workbook of its own, then seeds the scenario from it.
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
// One limitation for whoever picks up the next slice: reach. Five of the twelve compared fields —
// `state`, `setLog`, `unstructuredSetLog`, `loggedAt` and `legacyLog` — are empty on both sides of
// every pair, because every scenario holding athlete state still sits in
// `scenariosAwaitingAWorkbook`. Those fields are walked but not yet exercised.

// MARK: - The difference

private enum Drift: Hashable, CustomStringConvertible {
    case onlyInHandBuilt(String)
    case onlyInParsed(String)
    case field(_ address: String, _ name: String, handBuilt: String?, parsed: String?)

    var description: String {
        switch self {
        case .onlyInHandBuilt(let address):
            "\(address) — only in the hand-built graph"
        case .onlyInParsed(let address):
            "\(address) — only in the workbook's parse"
        case .field(let address, let name, let handBuilt, let parsed):
            "\(address).\(name) — hand-built \(quoted(handBuilt)) vs parsed \(quoted(parsed))"
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

    func compare(_ address: String, _ name: String, _ handBuilt: String?, _ parsed: String?) {
        guard handBuilt != parsed else { return }
        drift.append(.field(address, name, handBuilt: handBuilt, parsed: parsed))
    }
}

@MainActor
private func drift(handBuilt: Block, parsed: Block) -> [Drift] {
    let log = DriftLog()
    log.compare("block", "tabName", handBuilt.tabName, parsed.tabName)
    let handBuiltMaxes = handBuilt.trainingMaxes
    let parsedMaxes = parsed.trainingMaxes
    for lift in MainLift.allCases {
        log.compare("block", "trainingMax.\(lift)", text(handBuiltMaxes[lift]), text(parsedMaxes[lift]))
    }

    let handBuiltSessions = sessionsByAddress(handBuilt)
    let parsedSessions = sessionsByAddress(parsed)
    let sessions = Set(handBuiltSessions.keys).union(parsedSessions.keys)
    for address in sessions.sorted(by: { ($0.week, $0.day) < ($1.week, $1.day) }) {
        guard let handBuiltSession = handBuiltSessions[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedSession = parsedSessions[address] else {
            log.note(.onlyInHandBuilt(address.description))
            continue
        }
        // `Session.date` is deliberately not walked. The two sides are not in the same frame: the
        // graph authors an instant and the workbook authors a calendar day that
        // `SheetParser.parseDate` resolves in the machine's time zone, so a recorded pair of
        // instants passes in EDT and fails on a UTC runner. It is pinned instead, in both frames
        // and machine-independently, by `theWorkbookDateCellsAreTheHandBuiltDatesCalendarDays`.
        noteExerciseDrift(handBuilt: handBuiltSession, parsed: parsedSession, at: address, into: log)
    }
    return log.drift
}

@MainActor
private func noteExerciseDrift(handBuilt: Session, parsed: Session, at session: SessionAddress, into log: DriftLog) {
    let handBuiltExercises = exercisesByAddress(handBuilt, in: session)
    let parsedExercises = exercisesByAddress(parsed, in: session)
    for address in Set(handBuiltExercises.keys).union(parsedExercises.keys).sorted(by: { $0.order < $1.order }) {
        guard let handBuiltExercise = handBuiltExercises[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedExercise = parsedExercises[address] else {
            log.note(.onlyInHandBuilt(address.description))
            continue
        }
        let id = address.description
        log.compare(id, "name", handBuiltExercise.exerciseName.entered, parsedExercise.exerciseName.entered)
        log.compare(id, "baseName", handBuiltExercise.exerciseName.base, parsedExercise.exerciseName.base)
        log.compare(id, "cadence", handBuiltExercise.exerciseName.cadence, parsedExercise.exerciseName.cadence)
        log.compare(id, "coachNote", handBuiltExercise.coachNote, parsedExercise.coachNote)
        log.compare(id, "legacyLog", handBuiltExercise.legacyLog, parsedExercise.legacyLog)
        noteSetDrift(handBuilt: handBuiltExercise, parsed: parsedExercise, at: address, into: log)
    }
}

@MainActor
private func noteSetDrift(handBuilt: Exercise, parsed: Exercise, at exercise: ExerciseAddress, into log: DriftLog) {
    let handBuiltSets = setsByAddress(handBuilt, in: exercise)
    let parsedSets = setsByAddress(parsed, in: exercise)
    for address in Set(handBuiltSets.keys).union(parsedSets.keys).sorted(by: { $0.index < $1.index }) {
        guard let handBuiltSet = handBuiltSets[address] else {
            log.note(.onlyInParsed(address.description))
            continue
        }
        guard let parsedSet = parsedSets[address] else {
            log.note(.onlyInHandBuilt(address.description))
            continue
        }
        let id = address.description
        log.compare(id, "state", handBuiltSet.state.rawValue, parsedSet.state.rawValue)
        log.compare(id, "prescribedReps", handBuiltSet.prescribedReps, parsedSet.prescribedReps)
        log.compare(id, "prescribedLoad", handBuiltSet.prescribedLoad, parsedSet.prescribedLoad)
        log.compare(id, "percentOneRM", handBuiltSet.percentOneRM, parsedSet.percentOneRM)
        log.compare(id, "setLog", handBuiltSet.setLog?.formatted, parsedSet.setLog?.formatted)
        log.compare(id, "unstructuredSetLog", handBuiltSet.unstructuredSetLog, parsedSet.unstructuredSetLog)
        log.compare(id, "loggedAt", text(handBuiltSet.loggedAt), text(parsedSet.loggedAt))
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

/// `WorkbookScenario.block()`, the parse and build a sync makes, so the comparison runs against the
/// real interpretation rather than a second one written here. It stops where
/// `SyncCoordinator.replacePersistedBlock` begins: the overlays that follow, which re-apply pending
/// writes and preserve local `loggedAt`, are outside the harness and would matter the moment a
/// scenario holding athlete state is paired.
@MainActor
private func parsedBlock(_ scenario: WorkbookScenario) -> Block {
    // One tab, so "the Block tab" needs no selection rule here. A scenario that gains the
    // historical tabs Exercise History fills from has to say which tab it is pinning.
    #expect(scenario.workbook().tabs.count == 1, "\(scenario.rawValue) has more than one tab")
    #expect(scenario.parsedBlockTab().warnings == [], "\(scenario.rawValue) must parse cleanly before it can be compared")
    return scenario.block()
}

// MARK: - The declared pairs

/// A `WorkbookScenario` and the hand-built Block graph that fills the same fixture role: the
/// workbook was authored to reproduce what the graph renders, so the two describe one workout.
private struct PairedScenario: Sendable, CustomStringConvertible {
    let workbook: WorkbookScenario
    let handBuilt: UITestLaunch.Scenario

    var description: String { workbook.rawValue }
}

private let pairedScenarios: [PairedScenario] = [
    PairedScenario(workbook: .partialUpload, handBuilt: .partialUpload)
]

/// Workbooks no launch scenario seeds from. `fresh-block` is the CLI's default scenario
/// (`Sources/WorkoutCLI/Commands/InitCommand.swift`), and its shape is pinned by
/// `Tests/Unit/WorkbookScenarioTests.swift`, `Sources/WorkoutCLI/README.md`,
/// `scripts/viewed-session-across-sync.sh`, and the verify skill's `cli-headless.md`, not by a graph.
private let workbooksWithoutALaunchScenario: Set<WorkbookScenario> = [.freshBlock]

/// Launch scenarios with no workbook to compare against. `Tests/Unit/UITestFixtureBlockTests.swift`
/// still pins each one's `BlockShape`; what is missing is anything that checks that shape against
/// cells a coach could have typed. Each moves into `pairedScenarios` as its slice of #571 lands.
private let scenariosAwaitingAWorkbook: Set<UITestLaunch.Scenario> = [
    .perfectMoveOnCelebration,
    .completedOpenExercises,
    .openExercises,
    .longSession,
    .fullBlock
]

/// Every difference between the two sides today, in address order, with the side that is wrong
/// named per entry. Three of the nine hand-built Block factories — `currentSessionWithPendingSetsBlock`,
/// `partiallyLoggedSessionBlock`, `blockOverviewWithMixedSessionStatesBlock` — reach no launch
/// scenario and are used only by `Tests/Support/WorkoutScenarios.swift`, so they are out of this
/// list until #571 item 5 points that file at the same source.
private let recordedDrift: [WorkbookScenario: [Drift]] = [
    .partialUpload: [
        // The hand-built graph is wrong: it names each Accessory after its Session but hands over
        // the base name "Accessory" as a separate argument. The parser derives a base name from
        // the name cell by stripping a Cadence prefix only, so no cell yields that pair. The
        // workbook authors the base name the app renders (the Stage title, and
        // `PartiallyUploadedBlockUITests` asserts it) as the name too. The full name reaches only
        // the Live Activity and write targeting, which no `.partialUpload` run shows.
        .field("w3d1.e0", "name", handBuilt: "Accessory W3 D1", parsed: "Accessory"),
        .field("w4d1.e0", "name", handBuilt: "Accessory W4 D1", parsed: "Accessory")
    ]
]

// MARK: - The gate

@MainActor
@Test(arguments: pairedScenarios)
private func aPairedScenarioDriftsOnlyWhereRecorded(pair: PairedScenario) throws {
    let actual = drift(handBuilt: UITestFixture.block(for: pair.handBuilt), parsed: parsedBlock(pair.workbook))
    let expected = try #require(recordedDrift[pair.workbook])

    let unrecorded = actual.filter { !expected.contains($0) }
    let stale = expected.filter { !actual.contains($0) }

    #expect(unrecorded.isEmpty, "\(pair) drifts in ways nothing records:\n\(list(unrecorded))")
    #expect(stale.isEmpty, "\(pair) no longer drifts here, so delete these entries:\n\(list(stale))")
}

/// The one field the walk cannot record as a literal pair, pinned here instead.
///
/// `WorkoutFixtureFactory.session` re-derives `SessionProgressTracker`'s 7-day stride against the
/// reference date, so a hand-built Session date is an instant at UTC midnight. The workbook authors
/// a calendar day and `SheetParser.parseDate` resolves it as local midnight. The two sides are not
/// in the same frame, so a recorded pair of instants would read EDT on this machine and something
/// else on a UTC runner. Pinning each side in the frame it was authored in is machine-independent:
/// the hand-built instant's UTC calendar day and the parsed date's local calendar day must both be
/// the workbook's date cell, so under `TZ=UTC` the two sides are the same instant.
@MainActor
@Test func theWorkbookDateCellsAreTheHandBuiltDatesCalendarDays() throws {
    let handBuilt = sessionsByAddress(UITestFixture.block(for: .partialUpload))
    let parsed = sessionsByAddress(parsedBlock(.partialUpload))
    // Keyed by address and checked for coverage below, because the walk does not compare `date`:
    // this table is the only thing watching it, so a newly paired Session must not slip past.
    let expected: [String: String] = [
        "w1d1": "1/2/2001", "w1d2": "1/3/2001", "w1d3": "1/4/2001", "w1d4": "1/5/2001",
        "w2d1": "1/9/2001", "w2d2": "1/10/2001", "w2d3": "1/11/2001", "w2d4": "1/12/2001",
        "w3d1": "1/16/2001", "w3d2": "1/17/2001", "w3d3": "1/18/2001", "w3d4": "1/19/2001",
        "w4d1": "1/23/2001", "w4d2": "1/24/2001", "w4d3": "1/25/2001", "w4d4": "1/26/2001"
    ]
    func calendarDay(in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter
    }
    let utcDay = calendarDay(in: .gmt)
    let localDay = calendarDay(in: .current)

    #expect(Set(handBuilt.keys) == Set(parsed.keys))
    #expect(Set(expected.keys) == Set(parsed.keys.map(\.description)), "a paired Session has no pinned date")

    for address in parsed.keys.sorted(by: { ($0.week, $0.day) < ($1.week, $1.day) }) {
        let id = address.description
        let coachCell = try #require(expected[id])
        #expect(utcDay.string(from: try #require(handBuilt[address]?.date)) == coachCell, "\(id) left the stride")
        #expect(localDay.string(from: try #require(parsed[address]?.date)) == coachCell, "\(id) is not its date cell")
    }
}

@Test func everyScenarioIsEitherPairedOrRecordedAsAwaitingAWorkbook() {
    let paired = Set(pairedScenarios.map(\.handBuilt))
    let pairedWorkbooks = Set(pairedScenarios.map(\.workbook))
    #expect(pairedWorkbooks.isDisjoint(with: workbooksWithoutALaunchScenario))
    #expect(pairedWorkbooks.union(workbooksWithoutALaunchScenario) == Set(WorkbookScenario.allCases))
    #expect(Set(recordedDrift.keys) == pairedWorkbooks)
    #expect(paired.isDisjoint(with: scenariosAwaitingAWorkbook))
    #expect(paired.union(scenariosAwaitingAWorkbook) == Set(UITestLaunch.Scenario.allCases))
}

private func list(_ drift: [Drift]) -> String {
    drift.map { "  \($0)" }.joined(separator: "\n")
}

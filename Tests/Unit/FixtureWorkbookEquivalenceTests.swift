import Foundation
import Testing

@testable import WorkoutTracker

// Pins a hand-built fixture Block graph against the parse of the workbook paired with it.
// `Fixtures/WorkoutFixtureScenarios.swift` authors a Block graph by hand while
// `Fixtures/WorkbookScenarios.swift` authors cells the real parser reads, and until this file
// nothing compared the two — so a disagreement reached the Visual gate (ADR-0007) and was
// recorded there as intended appearance. Slice 1 of #571: the harness, not a migration.
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
// Two limitations for whoever picks up the next slice. The first is reach. Five of the twelve
// compared fields — `state`, `setLog`, `unstructuredSetLog`, `loggedAt` and `legacyLog` — are
// empty on both sides of the only pair, because every scenario holding athlete state still sits
// in `scenariosAwaitingAWorkbook`. Those fields are walked but not yet exercised. The second is
// that most of the recorded list says the two sides describe different workouts rather than that
// one drifted from the other, and it cannot shrink from the workbook side: `fresh-block`'s shape
// is pinned by
// `Tests/Unit/WorkbookScenarioTests.swift`, `Sources/WorkoutCLI/README.md`,
// `scripts/viewed-session-across-sync.sh`, and the verify skill's `cli-headless.md`. The
// intended end state is that `.partialUpload` gets a workbook of its own, that row replaces this
// one, and those entries are deleted rather than fixed one by one.

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

/// A Training Max reads back as the cell text a coach would have typed, so a recorded entry says
/// `"315"` rather than `"315.0"`. `Weight` owns that spelling.
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
        // and machine-independently, by `theHandBuiltSessionDatesCannotComeFromACoachDateCell`.
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
        log.compare(id, "name", handBuiltExercise.name, parsedExercise.name)
        log.compare(id, "baseName", handBuiltExercise.baseName, parsedExercise.baseName)
        log.compare(id, "cadence", handBuiltExercise.cadence, parsedExercise.cadence)
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
            week.sessions.map { (SessionAddress(week: week.number, day: $0.dayNumber), $0) }
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

/// `SheetParser.parse` then `BlockBuilder.makeBlock`, the two calls `SyncCoordinator.sync` makes,
/// so the comparison runs against the real interpretation rather than a second one written here.
/// It stops where `SyncCoordinator.replacePersistedBlock` begins: the overlays that follow, which
/// re-apply pending writes and preserve local `loggedAt`, are outside the harness and would matter
/// the moment a scenario holding athlete state is paired.
@MainActor
private func parsedBlock(_ scenario: WorkbookScenario) throws -> Block {
    let workbook = scenario.workbook()
    // One tab, so "the Block tab" needs no selection rule here. A scenario that gains the
    // historical tabs Exercise History fills from has to say which tab it is pinning.
    #expect(workbook.tabs.count == 1, "\(scenario.rawValue) has more than one tab")
    let tab = try #require(workbook.tabs.keys.sorted().first)
    let snapshot = try #require(workbook.tabs[tab]?.snapshot)
    let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
    #expect(parsed.warnings == [], "\(scenario.rawValue) must parse cleanly before it can be compared")
    return BlockBuilder.makeBlock(from: parsed.block)
}

// MARK: - The declared pairs

/// A `WorkbookScenario` and the hand-built Block graph that fills the same fixture role.
///
/// The role, not a resemblance, is what makes a row defensible, and it is readable from the
/// source: `fresh-block` is the CLI's default scenario (`Sources/WorkoutCLI/Commands/InitCommand.swift`)
/// and `.partialUpload` is the app's, as `UITestLaunch.scenario`'s fallback. Both are documented
/// as a Partially Uploaded Block. That is the strictest claim the source supports; it is
/// deliberately weaker than "these two describe the same workout", which nothing in the repo says
/// and which `recordedDrift` below shows to be false from Week 2 onward.
private struct PairedScenario: Sendable, CustomStringConvertible {
    let workbook: WorkbookScenario
    let handBuilt: UITestLaunch.Scenario

    var description: String { workbook.rawValue }
}

private let pairedScenarios: [PairedScenario] = [
    PairedScenario(workbook: .freshBlock, handBuilt: .partialUpload)
]

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
    .freshBlock: [
        // The hand-built graph is wrong: a Training Max is read from the Sheet's header area, and
        // `WorkoutFixtureFactory.block` hands over a literal triple instead. Which triple is
        // intended is a fixture choice for the migration; authoring it in Swift at all is the bug.
        .field("block", "trainingMax.squat", handBuilt: "315", parsed: "365"),
        .field("block", "trainingMax.bench", handBuilt: "225", parsed: "245"),
        .field("block", "trainingMax.deadlift", handBuilt: "405", parsed: "455"),

        // `Session.date` drifts too, on every paired Session, and is pinned by
        // `theHandBuiltSessionDatesCannotComeFromACoachDateCell` rather than listed here.

        // The workbook is the thin side: `WorkbookScenario.prescription` writes a Notes cell only
        // when a scenario passes one, so three of the four Coach Notes the UI fixture shows have no
        // cell to come from. A Coach Note is coach-authored content and belongs in column J.
        .field("w1d1.e0", "coachNote", handBuilt: "Brace hard off the floor, controlled descent.", parsed: nil),

        // The workbook is the thin side, for two different reasons that land on the same Sets.
        // Load: one Prescription Line carries one Load cell for every Set it prescribes, so a
        // workbook varies Load per Set only by authoring several Lines; `fresh-block` authors one
        // Line of three Sets where the graph wants RPE6/RPE7/RPE8. The graph is expressible, the
        // workbook just does not express it.
        // %1RM: `WorkbookScenario.prescription` writes the name, Sets, Reps, Load and Notes cells
        // and never the %1RM cell, even though `roleHeaderOffsets` declares the column. No workbook
        // in the repo fills it, so the %1RM arm of `LoadSuggestionEngine` is unreachable from any
        // workbook fixture.
        .field("w1d1.e0.s0", "prescribedLoad", handBuilt: "RPE6", parsed: "RPE7"),
        .field("w1d1.e0.s0", "percentOneRM", handBuilt: "75%", parsed: nil),
        .field("w1d1.e0.s1", "percentOneRM", handBuilt: "80%", parsed: nil),
        .field("w1d1.e0.s2", "prescribedLoad", handBuilt: "RPE8", parsed: "RPE7"),
        .field("w1d1.e0.s2", "percentOneRM", handBuilt: "85%", parsed: nil),

        // Undecided. One Coach Note, truncated on the workbook side, and the clearest evidence
        // that these two fixtures were once copied from each other: the workbook's text is a prefix
        // of the graph's to the character.
        .field(
            "w1d1.e1",
            "coachNote",
            handBuilt: "Start w/ 10 sec hold, proceed to rep range.",
            parsed: "Start w/ 10 sec hold"
        ),

        // The workbook is the thin side: no workbook in the repo writes a "Drop X%" Load, so the
        // Drop arm of `LoadSuggestionEngine` is unreachable from a workbook fixture the same way
        // the %1RM arm is. Whether this Exercise should be prescribed Drop 17.5% or RPE8 is a
        // fixture choice no source in the repo settles.
        .field("w1d1.e1.s0", "prescribedLoad", handBuilt: "Drop 17.5%", parsed: "RPE8"),
        .field("w1d1.e1.s1", "prescribedLoad", handBuilt: "Drop 17.5%", parsed: "RPE8"),

        .field("w1d2.e0", "coachNote", handBuilt: "Pause every rep.", parsed: nil),
        .field("w1d2.e0.s0", "prescribedLoad", handBuilt: "RPE6", parsed: "RPE7"),
        .field("w1d2.e0.s0", "percentOneRM", handBuilt: "70%", parsed: nil),
        .field("w1d2.e0.s1", "percentOneRM", handBuilt: "75%", parsed: nil),

        // The two fixtures disagree about the workout: the workbook prescribes three Sets of Bench
        // Press and the graph two. Undecided.
        .onlyInParsed("w1d2.e0.s2"),

        // Undecided, and sharper than a spelling drift: these are two Movements, not two spellings
        // of one. `MovementMatching.canonicalize` expands `bw` to `bodyweight`, so the two names
        // canonicalize to "pull up" and "bodyweight pull up" and score 0.39 against the 0.8
        // threshold (ADR-0013). Whichever name the fixture settles on, Exercise History silos
        // between the two, so this is not cosmetic. No source in the repo says which is intended.
        // Worth noting separately that `Factory.exercise` takes `baseName` as its own argument
        // while the parser derives it by stripping Cadence, so the graph can assert a base name its
        // own name could not produce. Here it does not, and both sides agree on the derivation.
        .field("w1d2.e1", "name", handBuilt: "Pull-Up", parsed: "BW Pull Up"),
        .field("w1d2.e1", "baseName", handBuilt: "Pull-Up", parsed: "BW Pull Up"),
        .field("w1d2.e1", "coachNote", handBuilt: "Use full range.", parsed: nil),

        // From here down the two fixtures are simply different workouts, and no source in the repo
        // says which the app is meant to boot into. The graph is a 4-Week by 4-Day grid whose Week 1 holds
        // two Available Sessions; the workbook is Week 1 with two Days and Week 2 with three. They
        // agree on exactly one thing past Week 1 — that w2d3 is an Unavailable Session — which is
        // why no w2d3 entry appears at all.
        .onlyInHandBuilt("w1d3"),
        .onlyInHandBuilt("w1d4"),

        .field("w2d1.e0", "name", handBuilt: "Deadlift", parsed: "Back Squat"),
        .field("w2d1.e0", "baseName", handBuilt: "Deadlift", parsed: "Back Squat"),
        .field("w2d1.e0", "coachNote", handBuilt: "Pull fast from the floor.", parsed: nil),
        .field("w2d1.e0.s0", "prescribedReps", handBuilt: "3", parsed: "5"),
        .field("w2d1.e0.s0", "prescribedLoad", handBuilt: "RPE6", parsed: "RPE7"),
        .field("w2d1.e0.s0", "percentOneRM", handBuilt: "75%", parsed: nil),
        .field("w2d1.e0.s1", "prescribedReps", handBuilt: "3", parsed: "5"),
        .field("w2d1.e0.s1", "percentOneRM", handBuilt: "80%", parsed: nil),
        .onlyInParsed("w2d1.e0.s2"),
        .onlyInParsed("w2d1.e1"),

        .onlyInParsed("w2d2.e0"),
        .onlyInParsed("w2d2.e1"),

        .onlyInHandBuilt("w2d4"),
        .onlyInHandBuilt("w3d1"),
        .onlyInHandBuilt("w3d2"),
        .onlyInHandBuilt("w3d3"),
        .onlyInHandBuilt("w3d4"),
        .onlyInHandBuilt("w4d1"),
        .onlyInHandBuilt("w4d2"),
        .onlyInHandBuilt("w4d3"),
        .onlyInHandBuilt("w4d4")
    ]
]

// MARK: - The gate

@MainActor
@Test(arguments: pairedScenarios)
private func aPairedScenarioDriftsOnlyWhereRecorded(pair: PairedScenario) throws {
    let actual = drift(handBuilt: UITestFixture.block(for: pair.handBuilt), parsed: try parsedBlock(pair.workbook))
    let expected = try #require(recordedDrift[pair.workbook])

    let unrecorded = actual.filter { !expected.contains($0) }
    let stale = expected.filter { !actual.contains($0) }

    #expect(unrecorded.isEmpty, "\(pair) drifts in ways nothing records:\n\(list(unrecorded))")
    #expect(stale.isEmpty, "\(pair) no longer drifts here, so delete these entries:\n\(list(stale))")
}

/// The one field the walk cannot record as a literal pair, pinned here instead.
///
/// `WorkoutFixtureFactory.session` re-derives `SessionProgressTracker`'s 7-day stride against the
/// reference date, so a hand-built Session date is an arithmetic artefact. The workbook authors a
/// calendar day and `SheetParser.parseDate` resolves it as local midnight. The two sides are not in
/// the same frame, so a recorded pair of instants would read EDT on this machine and something
/// else on a UTC runner. Pinning each side in the frame it was authored in is machine-independent
/// and stricter than the walk: it fails if either side's dates change, not merely if they differ.
@MainActor
@Test func theHandBuiltSessionDatesCannotComeFromACoachDateCell() throws {
    let handBuilt = sessionsByAddress(UITestFixture.block(for: .partialUpload))
    let parsed = sessionsByAddress(try parsedBlock(.freshBlock))
    // Keyed by address and checked for coverage below, because the walk does not compare `date`:
    // this table is the only thing watching it, so a newly paired Session must not slip past.
    let expected: [String: (strideSeconds: Double, coachCell: String)] = [
        "w1d1": (86_400, "5/4/2026"),
        "w1d2": (172_800, "5/6/2026"),
        "w2d1": (691_200, "5/11/2026"),
        "w2d2": (777_600, "5/13/2026"),
        "w2d3": (864_000, "5/15/2026")
    ]
    let coachDate = DateFormatter()
    coachDate.dateFormat = "M/d/yyyy"
    coachDate.locale = Locale(identifier: "en_US_POSIX")

    let paired = Set(handBuilt.keys).intersection(parsed.keys)
    #expect(Set(expected.keys) == Set(paired.map(\.description)), "a paired Session has no pinned date")

    for address in paired.sorted(by: { ($0.week, $0.day) < ($1.week, $1.day) }) {
        let id = address.description
        let row = try #require(expected[id])
        #expect(
            try #require(handBuilt[address]?.date) == Date(timeIntervalSinceReferenceDate: row.strideSeconds),
            "\(id) left the reference-date stride"
        )
        #expect(
            coachDate.string(from: try #require(parsed[address]?.date)) == row.coachCell,
            "\(id) is not the workbook's date cell"
        )
    }
}

@Test func everyScenarioIsEitherPairedOrRecordedAsAwaitingAWorkbook() {
    let paired = Set(pairedScenarios.map(\.handBuilt))
    #expect(Set(pairedScenarios.map(\.workbook)) == Set(WorkbookScenario.allCases))
    #expect(Set(recordedDrift.keys) == Set(WorkbookScenario.allCases))
    #expect(paired.isDisjoint(with: scenariosAwaitingAWorkbook))
    #expect(paired.union(scenariosAwaitingAWorkbook) == Set(UITestLaunch.Scenario.allCases))
}

private func list(_ drift: [Drift]) -> String {
    drift.map { "  \($0)" }.joined(separator: "\n")
}

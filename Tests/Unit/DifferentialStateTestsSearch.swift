import Foundation
import Testing
import WorkoutTracker

extension DifferentialStateTests {
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    enum Alphabet {
        static let sets = ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2", "w1d1.e1.s0", "w2d1.e0.s0", "w2d1.e1.s0", "w1d2.e0.s0"]
            .map { SetAddress($0)! }
        static let setLogs = ["185x5@8", "190x5@8", "200x3@9"]
        /// Only the cells the known rows edit, so a known divergence reached another way still classifies.
        static let coachEdits: [Operation] = [
            .coach(cell: "K15", value: "185.0x5@8"), .coach(cell: "K15", value: ""), .coach(cell: "K15", value: "185x5@8, 185x5@8"),
            .coach(cell: "K15", value: "300x5@7"), .coach(cell: "C15", value: "Front Squat"), .coach(cell: "C19", value: "Back Squat"),
            .coach(cell: "K19", value: "225x8"), .coach(cell: "K19", value: "")
        ]

        /// Each kind's weight and the ops it can draw, in what the harness knows. While a Move On
        /// Celebration is held the overlay is modal.
        @MainActor
        static func table(for harness: Harness) -> [(weight: Int, pool: [Operation])] {
            if harness.celebrated != nil {
                return [(3, [.dismissCelebration]), (2, [.flush]), (2, [.sync]), (3, coachEdits)]
            }
            let states = harness.setStates
            return [
                (6, sets.flatMap { set in setLogs.map { Operation.log(set: set, setLog: $0) } }),
                (2, sets.filter { states[$0] != "skipped" }.map(Operation.skip)),
                (1, sets.filter { states[$0] == "logged" || states[$0] == "skipped" }.map(Operation.deleteLog)),
                (1, harness.availableSessions.map(Operation.view)),
                (1, harness.viewed != harness.current ? [.makeCurrent] : []),
                (1, harness.viewed == harness.current ? [.requestMoveOn] : []),
                (2, [.flush]),
                (2, [.sync]),
                (4, coachEdits)
            ]
        }

        @MainActor
        static func draw(for harness: Harness, using generator: inout SplitMix64) -> Operation {
            let weighted = table(for: harness).flatMap { row in Array(repeating: row.pool, count: row.pool.isEmpty ? 0 : row.weight) }
            let pool = weighted[Int.random(in: weighted.indices, using: &generator)]
            return pool[Int.random(in: pool.indices, using: &generator)]
        }
    }

    fileprivate struct Tally {
        var hits = 0
        var refused = 0
        var i1Checks = 0
        var i2Checks = 0
        var known: [Int: (count: Int, firstIndex: Int)] = [:]
        var new: [String] = []
    }

    enum Search {
        static var isRequested: Bool { ProcessInfo.processInfo.environment["DIFF_SEQUENCES"] != nil }

        @MainActor
        static func run() async throws {
            let environment = ProcessInfo.processInfo.environment
            let sequences = try #require(environment["DIFF_SEQUENCES"].flatMap { Int($0) }, "DIFF_SEQUENCES is a count")
            let length = try environment["DIFF_LENGTH"].map { try #require(Int($0), "DIFF_LENGTH is a count") } ?? 10
            let seed =
                try environment["DIFF_SEED"].map { try #require(UInt64($0), "DIFF_SEED is a UInt64") }
                ?? UInt64.random(in: .min ... .max)
            let indices = try environment["DIFF_INDEX"].map { [try #require(Int($0), "DIFF_INDEX is an index")] } ?? Array(0..<sequences)
            emit("DIFF seed=\(seed) sequences=\(sequences) length=\(length) alphabet=1")
            var tally = Tally()
            for index in indices {
                try await explore(index: index, seed: seed, length: length, into: &tally)
            }
            for (number, hits) in tally.known.sorted(by: { $0.key < $1.key }) {
                withKnownIssue("#\(number)") {
                    Issue.record("\(hits.count) hits, the first at index \(hits.firstIndex)")
                }
            }
            for line in tally.new { Issue.record(Comment(rawValue: line)) }
            emit(
                "DIFF summary seed=\(seed) sequences=\(sequences) hits=\(tally.hits) known=\(tally.known.values.map(\.count).reduce(0, +)) "
                    + "new=\(tally.new.count) refused=\(tally.refused) i1Checks=\(tally.i1Checks) i2Checks=\(tally.i2Checks)"
            )
        }

        /// Sequence `index`: a refused tap, an `ApplicationError` of kind `.domain`, changed nothing, so
        /// it is counted and left out of the executed script; any other error fails the run.
        @MainActor
        private static func explore(index: Int, seed: UInt64, length: Int, into tally: inout Tally) async throws {
            let observation: Observation = index.isMultiple(of: 2) ? .everyStep : .endOnly
            var generator = SplitMix64(seed: seed ^ (UInt64(index) &* 0x9E37_79B9_7F4A_7C15))
            let harness = try await Harness()
            defer { (tally.i1Checks, tally.i2Checks) = (tally.i1Checks + harness.i1Checks, tally.i2Checks + harness.i2Checks) }
            var violation: Violation?
            do {
                for _ in 0..<length where violation == nil {
                    let op = Alphabet.draw(for: harness, using: &generator)
                    do {
                        violation = try await harness.perform(op)
                    } catch let error as ApplicationError where error.kind == .domain {
                        tally.refused += 1
                        continue
                    }
                    if violation == nil, observation == .everyStep { violation = try await harness.observe() }
                }
                if violation == nil, observation == .endOnly, !harness.executed.isEmpty { violation = try await harness.observe() }
            } catch {
                Issue.record(
                    Comment(rawValue: "index=\(index) \(observation.rawValue) threw \(error) after \(Operation.line(harness.executed))")
                )
                return
            }
            guard let violation else { return }
            tally.hits += 1
            let (known, minimized) = await classify(violation, harness.executed, observation)
            if let known {
                tally.known[known.number, default: (0, index)].count += 1
                emit("DIFF-KNOWN #\(known.number) index=\(index) \(observation.rawValue) \(Operation.line(minimized))")
            } else {
                let line = "DIFF-NEW index=\(index) \(observation.rawValue) \(violation) Minimized: \(Operation.line(minimized))"
                tally.new.append(line)
                emit(line)
            }
        }

        /// Every known divergence needs the Sheet to change under the app, so a hit is known when its
        /// invariant matches a row and the coach edits it still needs touch only that row's cells.
        @MainActor
        private static func classify(
            _ hit: Violation,
            _ script: [Operation],
            _ observation: Observation
        ) async -> (KnownDivergence?, [Operation]) {
            guard await fires(hit.invariant, script, observation) else { return (nil, script) }
            var dropped: Set<Int> = []
            for index in script.indices where script[index].coachCell != nil {
                let without = script.indices.filter { $0 != index && !dropped.contains($0) }.map { script[$0] }
                if await fires(hit.invariant, without, observation) { dropped.insert(index) }
            }
            let minimized = script.indices.filter { !dropped.contains($0) }.map { script[$0] }
            let cells = Set(minimized.compactMap(\.coachCell))
            guard !cells.isEmpty else { return (nil, minimized) }
            return (KnownDivergence.all.first { $0.invariant == hit.invariant && cells.isSubset(of: $0.coachCells) }, minimized)
        }

        /// A fresh harness each time; a re-run whose op throws counts as not firing.
        @MainActor
        private static func fires(_ invariant: Invariant, _ ops: [Operation], _ observation: Observation) async -> Bool {
            let violation = try? await Harness.run(ops, observing: observation)
            return violation?.invariant == invariant
        }

        /// Unbuffered, so a hung run still shows its seed.
        private static func emit(_ line: String) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
    }
}

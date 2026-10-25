import Foundation
import Testing
import WorkoutTracker

/// One long-lived application, driven through the public facade the way the UI drives the stores,
/// must agree with the state derived again from what it persisted: a second application reopened
/// over the same home (I1), and one that synced a copy of the workbook and settings into an empty
/// store (I2). The Sheet refuses no write unless the coach edited it since the last sync (I3), and
/// Move On never lands on an earlier Session (I4).
@MainActor
@Suite(.serialized) struct DifferentialStateTests {
    @Test(arguments: Replay.cases)
    func fixedReplayKeepsLiveAndRederivedStateEqual(_ replay: Replay, _ observation: Observation) async throws {
        let ops = try Operation.script(replay.script)
        for _ in 0..<replay.attempts {
            let violation = try await Harness.run(ops, observing: observation)
            #expect(violation == nil, Comment(rawValue: violation?.description ?? ""))
        }
    }

    @Test(arguments: KnownDivergence.all)
    func knownDivergenceStillReproduces(_ known: KnownDivergence) async throws {
        let violation = try await Harness.run(try Operation.script(known.script), observing: .endOnly)
        withKnownIssue("#\(known.number) \(known.title)") {
            if let violation { Issue.record(Comment(rawValue: violation.description)) }
        }
        #expect(violation?.symptom == known.symptom)
    }

    @Test(.enabled(if: Search.isRequested))
    func randomSequencesFindNoUnknownDivergence() async throws {
        try await Search.run()
    }
}

extension DifferentialStateTests {
    enum Invariant: String, Sendable {
        case reopened = "I1 live != reopened"
        case resynced = "I2 live != resynced"
        case refusal = "I3 refusal without coach edit"
        case backward = "I4 Move On went backward"
    }

    /// A violation with its values, its indices, and its Session taken out, so every hit of one bug
    /// shows the same symptom and a known row names only hits of its own bug.
    struct Symptom: Hashable, Sendable, CustomStringConvertible {
        let invariant: Invariant
        let shape: String

        init(_ invariant: Invariant, _ shape: String) {
            (self.invariant, self.shape) = (invariant, shape)
        }

        /// I1 and I2: the first differing key path, with `*` for its Session and each index, and
        /// which side holds a value there.
        static func difference(_ invariant: Invariant, at path: String, live: String?, other: String?) -> Symptom {
            let holder = live == nil ? "live absent" : other == nil ? "live only" : "both"
            return Symptom(invariant, "\(path.replacing(/^w\d+d\d+\./, with: "*.").replacing(/\[\d+\]/, with: "[*]")): \(holder)")
        }

        /// I3: each new refusal's kind, and whether an earlier refusal still stood. #552's next write
        /// builds its expectation from the refused one, so its refusal comes beside a standing one,
        /// and #685's came with none.
        static func refusal(_ messages: [String], standing: Bool) -> Symptom {
            let kinds = Set(messages.map(kind(of:))).sorted()
            return Symptom(.refusal, "\(kinds.joined(separator: " + ")), \(standing ? "beside a standing refusal" : "none standing")")
        }

        /// A value check is named by its cell, which only the values it quotes tell apart: a Last
        /// Set RPE holds a bare number or nothing, and a Set Log never does. A refusal that is not a
        /// value check is its whole message.
        private static func kind(of message: String) -> String {
            guard let check = message.firstMatch(of: /Expected '([^']*)', found '([^']*)'$/) else { return message }
            let rpe = [check.1, check.2].allSatisfy { $0.wholeMatch(of: /(\d+(\.\d+)?)?/) != nil }
            return rpe ? "Last Set RPE value check" : "Set Log value check"
        }

        static let backward = Symptom(.backward, "landed on an earlier Session")

        var description: String { "\(invariant.rawValue): \(shape)" }
    }

    struct Violation: Equatable, CustomStringConvertible {
        let symptom: Symptom
        let step: Int
        let op: Operation
        /// I1 and I2: the first differing key path and both values. I3: the new refusals. I4: where
        /// the celebration opened and where Move On landed.
        let detail: String
        let script: String

        var description: String { "\(symptom.invariant.rawValue) at step \(step) (\(op)): \(detail). Script: \(script)" }
    }

    /// I1 and I2 after every step, or after the last only. I3 and I4 hold on every step in both.
    enum Observation: String, CaseIterable, Sendable {
        case everyStep, endOnly
    }

    struct Replay: Sendable, CustomTestStringConvertible {
        let issue: Int
        let attempts: Int
        let observations: [Observation]
        let script: String

        var testDescription: String { "#\(issue)" }

        static let fixed = [
            Replay(
                issue: 813,
                attempts: 1,
                observations: Observation.allCases,
                script: "coach C19=Back Squat; sync; log w1d1.e1.s0 330x5@7; flush"
            ),
            Replay(
                issue: 685,
                attempts: 1,
                observations: Observation.allCases,
                script: "coach K15=185.0x5@8; sync; log w1d1.e0.s0 190x5@8; flush; sync"
            ),
            // With the fix reverted, 89 of 100 end-only attempts caught #972, so five miss together
            // about once in 60,000 runs. The request's returned AppSnapshot is part of what that
            // measured. I4 is checked on every step in both modes, so the cheaper one is enough.
            Replay(
                issue: 972,
                attempts: 5,
                observations: [.endOnly],
                script: "view w2d1; make-current; request-move-on; sync; dismiss-celebration"
            )
        ]

        static let cases = fixed.flatMap { replay in replay.observations.map { (replay, $0) } }
    }

    struct KnownDivergence: Sendable, CustomTestStringConvertible {
        let number: Int
        let title: String
        let symptom: Symptom
        let script: String

        var testDescription: String { "#\(number) \(title)" }

        var coachCells: Set<String> {
            Set(script.split(separator: ";").compactMap { Operation($0.trimmingCharacters(in: .whitespaces))?.coachCell })
        }

        /// A live entry the sync never retracts: the live application suggests a load from it.
        private static let staleEntry = Symptom(.resynced, "*.exercises[*].sets[*].loadSuggestion.basis.origin: live only")

        /// A hit is named by the first row with its symptom whose coach cells cover every cell the
        /// hit still needs, so a divergence the search reaches through other cells, or that shows
        /// another symptom there, has a row for each.
        static let all = [
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry outlives its renamed row",
                symptom: staleEntry,
                script: "log w1d1.e0.s0 185x5@8; flush; coach C15=Front Squat; sync"
            ),
            KnownDivergence(
                number: 812,
                title: "an Exercise History entry outlives its removed Set Log",
                symptom: staleEntry,
                script: "log w1d1.e0.s0 185x5@8; flush; coach K15=; sync"
            ),
            KnownDivergence(
                number: 961,
                title: "one history entry for two same-named Exercises",
                symptom: Symptom(.resynced, "*.exercises[*].sets[*].loadSuggestion.basis.origin: live absent"),
                script: "coach C19=Back Squat; coach K19=; sync; log w1d1.e0.s0 400x1@8; log w1d1.e1.s0 330x5@7; flush; "
                    + "skip w1d1.e1.s0; flush"
            ),
            KnownDivergence(
                number: 1047,
                title: "a coach's Legacy Log and a Set Log read twice",
                symptom: Symptom(.resynced, "app.sessions[*].completedSetCount: both"),
                script: "coach K19=225x8; sync; log w1d1.e1.s0 185x5@8; flush"
            ),
            KnownDivergence(
                number: 552,
                title: "a refused write replays onto every sync",
                symptom: Symptom(.refusal, "Set Log value check, beside a standing refusal"),
                script: "log w1d1.e0.s0 185x5@8; coach K15=300x5@7; flush; sync; log w1d1.e0.s0 190x5@8; flush"
            ),
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry from a coach's Set Log outlives its renamed row",
                symptom: staleEntry,
                script: "coach K15=185x5@8; sync; coach C15=Front Squat; sync"
            ),
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry outlives the Session's second Exercise, renamed",
                symptom: staleEntry,
                script: "log w1d1.e1.s0 185x5@8; flush; coach C19=Back Squat; sync"
            ),
            KnownDivergence(
                number: 812,
                title: "an Exercise History entry outlives the second Exercise's removed Set Log",
                symptom: staleEntry,
                script: "log w1d1.e1.s0 185x5@8; flush; coach K19=; sync"
            ),
            // The old name stays in the tab, on the other row, so this is #812's entry, not #964's.
            // Flushed before the swap, it does not go through #1109, whose misplaced write both
            // applications read alike.
            KnownDivergence(
                number: 812,
                title: "an Exercise History entry outlives its Set Log when the coach gives its name to another row",
                symptom: staleEntry,
                script: "log w1d1.e0.s2 185x5@8; flush; coach C15=Front Squat; coach C19=Back Squat; sync"
            ),
            KnownDivergence(
                number: 961,
                title: "live logging and sync keep different Set Logs for two same-named Exercises",
                symptom: Symptom(.resynced, "*.exercises[*].sets[*].loadSuggestion.basis.setLog: both"),
                script: "coach C19=Back Squat; sync; log w1d1.e0.s0 200x3@9; flush; log w1d1.e1.s0 190x5@8; "
                    + "log w1d1.e0.s0 185x5@8; flush"
            ),
            // A Set Log in another Session moves which Exercises the Current Session leaves open, so
            // the double reading shows there first.
            KnownDivergence(
                number: 1047,
                title: "a coach's Legacy Log and a Set Log read twice, seen in the open Exercises",
                symptom: Symptom(.resynced, "app.openExercises[*]: live absent"),
                script: "coach K19=225x8; sync; log w1d2.e0.s0 185x5@8; log w1d1.e1.s0 200x3@9; flush"
            ),
            // The later row's Legacy Log carries no RPE, so the entry the sync keeps suggests no load,
            // the shape a stale entry shows.
            KnownDivergence(
                number: 961,
                title: "live logging keeps the athlete's Set Log where sync keeps a same-named Exercise's Legacy Log",
                symptom: Symptom(.resynced, "*.exercises[*].sets[*].loadSuggestion.basis.origin: live only"),
                script: "coach C19=Back Squat; coach K19=225x8; sync; log w1d1.e0.s1 190x5@8; flush"
            ),
            KnownDivergence(
                number: 1113,
                title: "a Last Set RPE the coach leaves behind refuses the athlete's next log of that final Set",
                symptom: Symptom(.refusal, "Last Set RPE value check, none standing"),
                script: "log w1d1.e0.s2 200x3@9; flush; coach K15=; sync; log w1d1.e0.s2 200x3@9; flush"
            )
        ]
    }
}

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
    @Test(arguments: Replay.fixed, Observation.allCases)
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
        #expect(violation == nil || violation?.invariant == known.invariant)
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

    struct Violation: Equatable, CustomStringConvertible {
        let invariant: Invariant
        let step: Int
        let op: Operation
        /// I1 and I2: the first differing key path and both values. I3: the new refusals. I4: where
        /// the celebration opened and where Move On landed.
        let detail: String
        let script: String

        var description: String { "\(invariant.rawValue) at step \(step) (\(op)): \(detail). Script: \(script)" }
    }

    /// I1 and I2 after every step, or after the last only. I3 and I4 hold on every step in both.
    enum Observation: String, CaseIterable, Sendable {
        case everyStep, endOnly
    }

    struct Replay: Sendable, CustomTestStringConvertible {
        let issue: Int
        let attempts: Int
        let script: String

        var testDescription: String { "#\(issue)" }

        static let fixed = [
            Replay(issue: 813, attempts: 1, script: "coach C19=Back Squat; sync; log w1d1.e1.s0 330x5@7; flush"),
            Replay(issue: 685, attempts: 1, script: "coach K15=185.0x5@8; sync; log w1d1.e0.s0 190x5@8; flush; sync"),
            // With the fix reverted, one run catches #972 15 to 17 times in 20, so five make a miss rare.
            // The request's returned AppSnapshot is part of what that measured.
            Replay(issue: 972, attempts: 5, script: "view w2d1; make-current; request-move-on; sync; dismiss-celebration")
        ]
    }

    struct KnownDivergence: Sendable, CustomTestStringConvertible {
        let number: Int
        let title: String
        let invariant: Invariant
        let script: String

        var testDescription: String { "#\(number) \(title)" }

        var coachCells: Set<String> {
            Set(script.split(separator: ";").compactMap { Operation($0.trimmingCharacters(in: .whitespaces))?.coachCell })
        }

        /// A hit is named by the first row with its invariant whose coach cells cover every cell the
        /// hit still needs, so a divergence the search reaches through other cells has a row for each.
        static let all = [
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry outlives its renamed row",
                invariant: .resynced,
                script: "log w1d1.e0.s0 185x5@8; flush; coach C15=Front Squat; sync"
            ),
            KnownDivergence(
                number: 812,
                title: "an Exercise History entry outlives its removed Set Log",
                invariant: .resynced,
                script: "log w1d1.e0.s0 185x5@8; flush; coach K15=; sync"
            ),
            KnownDivergence(
                number: 961,
                title: "one history entry for two same-named Exercises",
                invariant: .resynced,
                script: "coach C19=Back Squat; coach K19=; sync; log w1d1.e0.s0 400x1@8; log w1d1.e1.s0 330x5@7; flush; "
                    + "skip w1d1.e1.s0; flush"
            ),
            KnownDivergence(
                number: 1047,
                title: "a coach's Legacy Log and a Set Log read twice",
                invariant: .resynced,
                script: "coach K19=225x8; sync; log w1d1.e1.s0 185x5@8; flush"
            ),
            KnownDivergence(
                number: 552,
                title: "a refused write replays onto every sync",
                invariant: .refusal,
                script: "log w1d1.e0.s0 185x5@8; coach K15=300x5@7; flush; sync; log w1d1.e0.s0 190x5@8; flush"
            ),
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry from a coach's Set Log outlives its renamed row",
                invariant: .resynced,
                script: "coach K15=185x5@8; sync; coach C15=Front Squat; sync"
            ),
            // The pending Set Log follows its Exercise's name onto the other row, so nothing stays
            // pending and I2 sees the entry the rename left behind.
            KnownDivergence(
                number: 964,
                title: "an Exercise History entry outlives its row when the coach gives its name to another",
                invariant: .resynced,
                script: "log w1d1.e0.s2 185x5@8; coach C15=Front Squat; coach C19=Back Squat; sync"
            )
        ]
    }
}

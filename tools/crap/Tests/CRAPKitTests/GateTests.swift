import Testing

@testable import CRAPKit

private func report(_ rows: [(name: String, cc: Int, crap: Double?)]) -> Report {
    let functions = rows.map { row in
        FunctionRow(
            file: "A.swift",
            name: row.name,
            kind: .function,
            startLine: 1,
            endLine: 2,
            cc: row.cc,
            linesInstrumented: row.crap == nil ? 0 : 2,
            linesCovered: 0,
            coverage: row.crap == nil ? nil : 0,
            crap: row.crap
        )
    }
    return Report(
        generatedAt: "2026-01-01T00:00:00Z",
        threshold: 12,
        sources: [],
        excludes: [],
        totals: Totals(
            functions: functions.count,
            measured: functions.count,
            unmeasured: 0,
            aboveThreshold: 0,
            maxCrap: 0,
            linesInstrumented: 0,
            linesCovered: 0
        ),
        functions: functions
    )
}

private func evaluate(_ report: Report, _ baseline: [BaselineEntry]) -> GateOutcome {
    Gate.evaluate(report: report, baseline: baseline, threshold: 12, tolerance: 0.5)
}

@Suite struct GateTests {
    @Test func cleanWhenEveryViolationIsBaselinedAtItsRecordedScore() {
        let outcome = evaluate(
            report([("A.f()", 5, 30.0), ("A.g()", 2, 4.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)]
        )
        #expect(outcome.findings.isEmpty)
        #expect(outcome.isClean)
        #expect(outcome.exitCode == 0)
    }

    @Test func newViolation() {
        let outcome = evaluate(report([("A.f()", 5, 30.0)]), [])
        #expect(outcome.findings == [.newViolation(file: "A.swift", name: "A.f()", crap: 30.0, threshold: 12)])
        #expect(outcome.exitCode == 1)
    }

    @Test func worsened() {
        let outcome = evaluate(
            report([("A.f()", 6, 42.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)]
        )
        #expect(
            outcome.findings == [
                .worsened(file: "A.swift", name: "A.f()", crap: 42.0, recorded: 30.0, tolerance: 0.5)
            ]
        )
        #expect(outcome.exitCode == 1)
    }

    @Test func staleWhenTheFunctionIsGone() {
        let outcome = evaluate(report([]), [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)])
        #expect(outcome.findings == [.stale(file: "A.swift", name: "A.f()", recorded: 30.0, reason: .missing)])
        #expect(outcome.exitCode == 1)
    }

    @Test func staleWhenTheFunctionDroppedToTheThreshold() {
        let outcome = evaluate(
            report([("A.f()", 5, 9.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)]
        )
        #expect(
            outcome.findings == [
                .stale(file: "A.swift", name: "A.f()", recorded: 30.0, reason: .atOrBelowThreshold)
            ]
        )
        #expect(outcome.exitCode == 1)
    }

    @Test func improvedIsANoteNotAFailure() {
        let outcome = evaluate(
            report([("A.f()", 4, 20.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)]
        )
        #expect(outcome.findings == [.improved(file: "A.swift", name: "A.f()", crap: 20.0, recorded: 30.0)])
        #expect(outcome.isClean)
        #expect(outcome.exitCode == 0)
        #expect(outcome.notes.count == 1)
    }

    @Test func staleMessageNamesTheLineToDelete() {
        let message = Finding.stale(file: "A.swift", name: "A.f()", recorded: 30.0, reason: .missing).message
        #expect(message.contains("A.swift\tA.f()\t30.0"))
    }

    @Test func toleranceAbsorbsSmallMovement() {
        let outcome = evaluate(
            report([("A.f()", 5, 30.3)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)]
        )
        #expect(outcome.findings.isEmpty)
    }

    @Test func baselineRoundTrips() {
        let text = Baseline.render(report: report([("A.f()", 5, 30.04), ("A.g()", 2, 4.0)]), threshold: 12)
        #expect(text == "file\tname\tcrap\nA.swift\tA.f()\t30.0\n")
        #expect(Baseline.parse(text: text) == [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)])
    }
}

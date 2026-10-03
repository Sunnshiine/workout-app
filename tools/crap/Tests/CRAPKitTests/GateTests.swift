import Testing

@testable import CRAPKit

private func report(_ rows: [(name: String, cc: Int, crap: Double?)], coverage: Double = 0) -> Report {
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
            coverage: row.crap == nil ? nil : coverage,
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
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")]
        )
        #expect(outcome.findings.isEmpty)
        #expect(outcome.isClean)
        #expect(outcome.exitCode == 0)
    }

    @Test func newViolation() {
        let outcome = evaluate(report([("A.f()", 5, 30.0)]), [])
        #expect(
            outcome.findings == [
                .newViolation(file: "A.swift", name: "A.f()", crap: 30.0, threshold: 12, cc: 5, coverage: 0)
            ]
        )
        #expect(outcome.exitCode == 1)
    }

    @Test func worsened() {
        let outcome = evaluate(
            report([("A.f()", 6, 42.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")]
        )
        #expect(
            outcome.findings == [
                .worsened(file: "A.swift", name: "A.f()", crap: 42.0, recorded: 30.0, tolerance: 0.5, cc: 6, coverage: 0)
            ]
        )
        #expect(outcome.exitCode == 1)
    }

    @Test func worsenedCarriesTheFunctionsCCAndCoverage() {
        let outcome = evaluate(
            report([("A.f()", 14, 14.0)], coverage: 1),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 12.5, reason: "held")]
        )
        #expect(
            outcome.findings == [
                .worsened(file: "A.swift", name: "A.f()", crap: 14.0, recorded: 12.5, tolerance: 0.5, cc: 14, coverage: 1)
            ]
        )
    }

    @Test func staleWhenTheFunctionIsGone() {
        let outcome = evaluate(report([]), [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")])
        #expect(outcome.findings == [.stale(file: "A.swift", name: "A.f()", recorded: 30.0, reason: .missing)])
        #expect(outcome.exitCode == 1)
    }

    @Test func staleWhenTheFunctionDroppedToTheThreshold() {
        let outcome = evaluate(
            report([("A.f()", 5, 9.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")]
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
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")]
        )
        #expect(outcome.findings == [.improved(file: "A.swift", name: "A.f()", crap: 20.0, recorded: 30.0)])
        #expect(outcome.isClean)
        #expect(outcome.exitCode == 0)
        #expect(outcome.notes.count == 1)
    }

    @Test func staleMessageNamesTheRowToDelete() {
        let message = Finding.stale(file: "A.swift", name: "A.f()", recorded: 30.0, reason: .missing).message
        #expect(message.hasPrefix("stale         A.swift  A.f()  baseline records 30.0"))
        #expect(message.hasSuffix("delete its line from the baseline or rerun scripts/crap.sh baseline"))
    }

    @Test func newViolationOverTheThresholdAtFullCoverageNamesSimplifying() {
        let message = Finding.newViolation(
            file: "A.swift",
            name: "A.f()",
            crap: 7.0,
            threshold: 6,
            cc: 7,
            coverage: 1
        ).message
        #expect(
            message
                == "newViolation  A.swift  A.f()  crap 7.0 > threshold 6.0 at cc 7 and coverage 100%, not in the baseline; "
                + "cc alone is over 6.0 and crap never drops below cc, so testing alone cannot help; "
                + "simplify it down to 6.0 or below, "
                + "or, as a last resort, run scripts/crap.sh baseline to add its row and then give the row a reason"
        )
    }

    @Test func newViolationUnderCoveredNamesTesting() {
        let message = Finding.newViolation(
            file: "A.swift",
            name: "A.f()",
            crap: 30.0,
            threshold: 6,
            cc: 5,
            coverage: 0
        ).message
        #expect(
            message
                == "newViolation  A.swift  A.f()  crap 30.0 > threshold 6.0 at cc 5 and coverage 0%, not in the baseline; "
                + "full coverage brings crap down to its cc, 5, so test it down to 6.0 or below, "
                + "or, as a last resort, run scripts/crap.sh baseline to add its row and then give the row a reason"
        )
    }

    @Test func newViolationWithCCAtTheThresholdNamesTesting() {
        let message = Finding.newViolation(
            file: "A.swift",
            name: "A.f()",
            crap: 6.6,
            threshold: 6,
            cc: 6,
            coverage: 0.75
        ).message
        #expect(
            message
                == "newViolation  A.swift  A.f()  crap 6.6 > threshold 6.0 at cc 6 and coverage 75%, not in the baseline; "
                + "full coverage brings crap down to its cc, 6, so test it down to 6.0 or below, "
                + "or, as a last resort, run scripts/crap.sh baseline to add its row and then give the row a reason"
        )
    }

    @Test func worsenedByLostCoverageNamesTesting() {
        let message = Finding.worsened(
            file: "A.swift",
            name: "A.f()",
            crap: 10.3,
            recorded: 9.0,
            tolerance: 0.5,
            cc: 9,
            coverage: 0.75
        ).message
        #expect(
            message
                == "worsened      A.swift  A.f()  crap 10.3 > baseline 9.0 + tolerance 0.5 at cc 9 and coverage 75%; "
                + "full coverage brings crap down to its cc, 9, so test it down to 9.5 or below, "
                + "or, as a last resort, raise its crap in the baseline by hand and say why in its reason "
                + "(scripts/crap.sh baseline never raises a score)"
        )
    }

    @Test func worsenedByAGainedBranchNamesSimplifying() {
        let message = Finding.worsened(
            file: "A.swift",
            name: "A.f()",
            crap: 8.0,
            recorded: 7.0,
            tolerance: 0.5,
            cc: 8,
            coverage: 1
        ).message
        #expect(
            message
                == "worsened      A.swift  A.f()  crap 8.0 > baseline 7.0 + tolerance 0.5 at cc 8 and coverage 100%; "
                + "cc alone is over 7.5 and crap never drops below cc, so testing alone cannot help; "
                + "simplify it down to 7.5 or below, "
                + "or, as a last resort, raise its crap in the baseline by hand and say why in its reason "
                + "(scripts/crap.sh baseline never raises a score)"
        )
    }

    @Test func worsenedWithCCAtTheLimitNamesTesting() {
        let message = Finding.worsened(
            file: "A.swift",
            name: "A.f()",
            crap: 8.9,
            recorded: 7.5,
            tolerance: 0.5,
            cc: 8,
            coverage: 0.9
        ).message
        #expect(
            message
                == "worsened      A.swift  A.f()  crap 8.9 > baseline 7.5 + tolerance 0.5 at cc 8 and coverage 90%; "
                + "full coverage brings crap down to its cc, 8, so test it down to 8.0 or below, "
                + "or, as a last resort, raise its crap in the baseline by hand and say why in its reason "
                + "(scripts/crap.sh baseline never raises a score)"
        )
    }

    @Test func unexplainedRowFailsUntilItGivesAReason() throws {
        let outcome = evaluate(
            report([("A.f()", 5, 30.0)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: " ")]
        )
        #expect(outcome.findings == [.unexplained(file: "A.swift", name: "A.f()")])
        #expect(outcome.exitCode == 1)
        let finding = try #require(outcome.findings.first)
        #expect(
            finding.message
                == "unexplained   A.swift  A.f()  baseline row has no reason; "
                + "write why it stays above the threshold in its reason column"
        )
    }

    @Test func toleranceAbsorbsSmallMovement() {
        let outcome = evaluate(
            report([("A.f()", 5, 30.3)]),
            [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "held")]
        )
        #expect(outcome.findings.isEmpty)
    }

    @Test func baselineRoundTrips() {
        let text = Baseline.render(report: report([("A.f()", 5, 30.04), ("A.g()", 2, 4.0)]), threshold: 12)
        #expect(text == "file\tname\tcrap\treason\nA.swift\tA.f()\t30.0\t\n")
        #expect(Baseline.parse(text: text) == [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0)])
    }

    @Test func baselineKeepsAReasonWhileItsRowSurvivesAndDropsItWithTheRow() {
        let prior = [
            BaselineEntry(file: "A.swift", name: "A.f()", crap: 31.0, reason: "device I/O"),
            BaselineEntry(file: "A.swift", name: "A.gone()", crap: 20.0, reason: "obsolete")
        ]
        let text = Baseline.render(report: report([("A.f()", 5, 30.0), ("A.h()", 4, 14.0)]), threshold: 12, carrying: prior)
        #expect(text == "file\tname\tcrap\treason\nA.swift\tA.f()\t30.0\tdevice I/O\nA.swift\tA.h()\t14.0\t\n")
    }

    @Test func rewritingTheBaselineForANewRowLeavesAWorsenedRowFailing() {
        let measured = report([("A.f()", 6, 42.0), ("A.n()", 4, 14.0)])
        let prior = [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "device I/O")]
        let rewritten = Baseline.parse(text: Baseline.render(report: measured, threshold: 12, carrying: prior))
        #expect(
            evaluate(measured, rewritten).findings == [
                .worsened(file: "A.swift", name: "A.f()", crap: 42.0, recorded: 30.0, tolerance: 0.5, cc: 6, coverage: 0),
                .unexplained(file: "A.swift", name: "A.n()")
            ]
        )
    }

    @Test func baselineWrittenBeforeTheReasonColumnStillParses() {
        let entries = Baseline.parse(text: "file\tname\tcrap\nA.swift\tA.f()\t30.0\n")
        #expect(entries == [BaselineEntry(file: "A.swift", name: "A.f()", crap: 30.0, reason: "")])
    }
}

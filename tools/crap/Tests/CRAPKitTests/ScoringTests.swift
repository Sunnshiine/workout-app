import Testing

@testable import CRAPKit

private let twoFunctionFile = """
    struct A {
        func covered() {
            print(1)
        }
        func uncovered() {
            print(2)
        }
        func never() {
            print(3)
        }
    }
    """

private let lcov = """
    SF:A.swift
    FN:2,covered
    DA:2,4
    DA:3,4
    DA:5,0
    DA:6,0
    end_of_record
    """

@Suite struct ScoringTests {
    @Test func lcovParsesOnlyLineRecords() {
        #expect(LCOV.parse(text: lcov) == ["A.swift": [2: 4, 3: 4, 5: 0, 6: 0]])
    }

    @Test func repeatedRecordsForOneLineAreSummed() {
        let text = "SF:A.swift\nDA:2,1\nend_of_record\nSF:A.swift\nDA:2,3\nend_of_record"
        #expect(LCOV.parse(text: text) == ["A.swift": [2: 4]])
    }

    @Test func coverageJoinCountsOnlyInstrumentedLinesInTheSpan() {
        let report = Scorer.score(
            scanned: SwiftFunctionScanner.scan(source: twoFunctionFile, file: "A.swift"),
            coverage: LCOV.parse(text: lcov),
            threshold: 12
        )
        let rows = Dictionary(uniqueKeysWithValues: report.functions.map { ($0.name, $0) })
        #expect(rows["A.covered()"]?.linesInstrumented == 2)
        #expect(rows["A.covered()"]?.linesCovered == 2)
        #expect(rows["A.covered()"]?.coverage == 1.0)
        #expect(rows["A.covered()"]?.crap == 1.0)
        #expect(rows["A.uncovered()"]?.linesInstrumented == 2)
        #expect(rows["A.uncovered()"]?.linesCovered == 0)
        #expect(rows["A.uncovered()"]?.crap == 2.0)
    }

    @Test func aFunctionWithNoLineRecordsIsUnmeasured() {
        let report = Scorer.score(
            scanned: SwiftFunctionScanner.scan(source: twoFunctionFile, file: "A.swift"),
            coverage: LCOV.parse(text: lcov),
            threshold: 12
        )
        let never = report.functions.first { $0.name == "A.never()" }
        #expect(never?.linesInstrumented == 0)
        #expect(never?.coverage == nil)
        #expect(never?.crap == nil)
        #expect(report.totals.unmeasured == 1)
        #expect(report.totals.measured == 2)
        #expect(report.functions.last?.name == "A.never()")
    }

    @Test func crapArithmetic() {
        #expect(crapScore(cc: 5, coverage: 0) == 30.0)
        #expect(crapScore(cc: 5, coverage: 1) == 5.0)
        #expect(crapScore(cc: 4, coverage: 0.5) == 6.0)
    }

    @Test func totalsCountViolations() {
        let report = Scorer.score(
            scanned: [
                ScannedFunction(
                    file: "A.swift",
                    name: "A.big()",
                    kind: .function,
                    startLine: 1,
                    endLine: 3,
                    cc: 5,
                    nestedSpans: []
                )
            ],
            coverage: ["A.swift": [1: 0, 2: 0, 3: 0]],
            threshold: 12
        )
        #expect(report.totals.aboveThreshold == 1)
        #expect(report.totals.maxCrap == 30.0)
        #expect(report.totals.linesInstrumented == 3)
        #expect(report.totals.linesCovered == 0)
    }

    @Test func excludeGlobsMatchRelativePaths() {
        #expect(SourceScan.isExcluded(path: "WorkoutTracker/Views/Home.swift", excludes: ["WorkoutTracker/Views/*"]))
        #expect(!SourceScan.isExcluded(path: "WorkoutTracker/Stores/Sync.swift", excludes: ["WorkoutTracker/Views/*"]))
    }

    @Test func absolutePathsBecomeRepositoryRelative() {
        #expect(SourceScan.relativize(path: "/repo/WorkoutTracker/A.swift", root: "/repo") == "WorkoutTracker/A.swift")
    }
}

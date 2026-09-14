import Foundation

public enum Scorer {
    public static func score(
        scanned: [ScannedFunction],
        coverage: [String: [Int: Int]],
        threshold: Double
    ) -> Report {
        var rows: [FunctionRow] = []
        rows.reserveCapacity(scanned.count)
        for function in scanned {
            let hits = coverage[function.file] ?? [:]
            var instrumented = 0
            var covered = 0
            for line in function.ownedLines() {
                guard let count = hits[line] else { continue }
                instrumented += 1
                if count > 0 { covered += 1 }
            }
            let fraction = instrumented > 0 ? Double(covered) / Double(instrumented) : nil
            rows.append(
                FunctionRow(
                    file: function.file,
                    name: function.name,
                    kind: function.kind,
                    startLine: function.startLine,
                    endLine: function.endLine,
                    cc: function.cc,
                    linesInstrumented: instrumented,
                    linesCovered: covered,
                    coverage: fraction,
                    crap: fraction.map { roundedToOneDecimal(crapScore(cc: function.cc, coverage: $0)) }
                )
            )
        }
        rows.sort(by: ordering)

        let measured = rows.filter(\.isMeasured)
        let totals = Totals(
            functions: rows.count,
            measured: measured.count,
            unmeasured: rows.count - measured.count,
            aboveThreshold: measured.count { ($0.crap ?? 0) > threshold },
            maxCrap: measured.compactMap(\.crap).max() ?? 0,
            linesInstrumented: rows.reduce(0) { $0 + $1.linesInstrumented },
            linesCovered: rows.reduce(0) { $0 + $1.linesCovered }
        )
        return Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            threshold: threshold,
            sources: [],
            excludes: [],
            totals: totals,
            functions: rows
        )
    }

    private static func ordering(_ lhs: FunctionRow, _ rhs: FunctionRow) -> Bool {
        switch (lhs.crap, rhs.crap) {
        case (let left?, let right?) where left != right:
            return left > right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        return lhs.startLine < rhs.startLine
    }
}

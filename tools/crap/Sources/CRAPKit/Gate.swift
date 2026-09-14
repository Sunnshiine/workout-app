import Foundation

public struct BaselineEntry: Sendable, Equatable {
    public var file: String
    public var name: String
    public var crap: Double

    public init(file: String, name: String, crap: Double) {
        self.file = file
        self.name = name
        self.crap = crap
    }
}

public enum StaleReason: String, Sendable {
    case missing
    case atOrBelowThreshold
    case unmeasured
}

public enum Finding: Sendable, Equatable {
    case newViolation(file: String, name: String, crap: Double, threshold: Double)
    case worsened(file: String, name: String, crap: Double, recorded: Double, tolerance: Double)
    case stale(file: String, name: String, recorded: Double, reason: StaleReason)
    case improved(file: String, name: String, crap: Double, recorded: Double)

    public var fails: Bool {
        switch self {
        case .newViolation, .worsened, .stale: true
        case .improved: false
        }
    }

    public var message: String {
        switch self {
        case .newViolation(let file, let name, let crap, let threshold):
            "newViolation  \(file)  \(name)  crap \(format(crap)) > threshold \(format(threshold)), not in the baseline"
        case .worsened(let file, let name, let crap, let recorded, let tolerance):
            "worsened      \(file)  \(name)  crap \(format(crap)) > baseline \(format(recorded)) + tolerance \(format(tolerance))"
        case .stale(let file, let name, let recorded, let reason):
            "stale         \(file)  \(name)  baseline records \(format(recorded)) but \(reason.explanation); "
                + "delete the line `\(file)\t\(name)\t\(format(recorded))` from the baseline "
                + "or rerun scripts/crap.sh baseline"
        case .improved(let file, let name, let crap, let recorded):
            "improved      \(file)  \(name)  crap \(format(crap)) < baseline \(format(recorded)); "
                + "rerun scripts/crap.sh baseline to bank it"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

extension StaleReason {
    fileprivate var explanation: String {
        switch self {
        case .missing: "the function is no longer in the report"
        case .atOrBelowThreshold: "the function is now at or below the threshold"
        case .unmeasured: "the function is no longer measured"
        }
    }
}

public struct GateOutcome: Sendable {
    public var findings: [Finding]

    public init(findings: [Finding]) {
        self.findings = findings
    }

    public var failures: [Finding] { findings.filter(\.fails) }
    public var notes: [Finding] { findings.filter { !$0.fails } }
    public var isClean: Bool { failures.isEmpty }
    public var exitCode: Int32 { isClean ? 0 : 1 }
}

public enum Gate {
    public static func evaluate(
        report: Report,
        baseline: [BaselineEntry],
        threshold: Double,
        tolerance: Double
    ) -> GateOutcome {
        var rows: [Key: FunctionRow] = [:]
        for row in report.functions {
            rows[Key(file: row.file, name: row.name)] = row
        }
        var recorded: Set<Key> = []
        var findings: [Finding] = []

        for entry in baseline.sorted(by: { ($0.file, $0.name) < ($1.file, $1.name) }) {
            let key = Key(file: entry.file, name: entry.name)
            recorded.insert(key)
            guard let row = rows[key] else {
                findings.append(.stale(file: entry.file, name: entry.name, recorded: entry.crap, reason: .missing))
                continue
            }
            guard let crap = row.crap else {
                findings.append(.stale(file: entry.file, name: entry.name, recorded: entry.crap, reason: .unmeasured))
                continue
            }
            if crap <= threshold {
                findings.append(
                    .stale(file: entry.file, name: entry.name, recorded: entry.crap, reason: .atOrBelowThreshold)
                )
            } else if crap > entry.crap + tolerance {
                findings.append(
                    .worsened(
                        file: entry.file,
                        name: entry.name,
                        crap: crap,
                        recorded: entry.crap,
                        tolerance: tolerance
                    )
                )
            } else if crap < entry.crap - tolerance {
                findings.append(.improved(file: entry.file, name: entry.name, crap: crap, recorded: entry.crap))
            }
        }

        for row in report.functions {
            guard let crap = row.crap, crap > threshold else { continue }
            let key = Key(file: row.file, name: row.name)
            guard !recorded.contains(key) else { continue }
            findings.append(.newViolation(file: row.file, name: row.name, crap: crap, threshold: threshold))
        }
        return GateOutcome(findings: findings)
    }

    private struct Key: Hashable {
        var file: String
        var name: String
    }
}

public enum Baseline {
    public static let header = "file\tname\tcrap"

    public static func parse(text: String) -> [BaselineEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard line != header else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let crap = Double(fields[2]) else { return nil }
            return BaselineEntry(file: String(fields[0]), name: String(fields[1]), crap: crap)
        }
    }

    public static func render(report: Report, threshold: Double) -> String {
        let entries =
            report.functions
            .filter { ($0.crap ?? 0) > threshold }
            .sorted { ($0.file, $0.name) < ($1.file, $1.name) }
            .map { "\($0.file)\t\($0.name)\t\(String(format: "%.1f", $0.crap ?? 0))" }
        return ([header] + entries).joined(separator: "\n") + "\n"
    }
}

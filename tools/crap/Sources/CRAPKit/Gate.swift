import Foundation

public struct BaselineEntry: Sendable, Equatable {
    public var file: String
    public var name: String
    public var crap: Double
    /// Why the row is held above the threshold. Written by hand, kept across `crap baseline` rewrites
    /// while the row survives, and gone with the row. The gate fails a row whose reason is empty.
    public var reason: String

    public init(file: String, name: String, crap: Double, reason: String = "") {
        self.file = file
        self.name = name
        self.crap = crap
        self.reason = reason
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
    case unexplained(file: String, name: String)

    public var fails: Bool {
        switch self {
        case .newViolation, .worsened, .stale, .unexplained: true
        case .improved: false
        }
    }

    public var message: String {
        switch self {
        case .newViolation(let file, let name, let crap, let threshold):
            "newViolation  \(file)  \(name)  crap \(format(crap)) > threshold \(format(threshold)), not in the baseline; "
                + "test or simplify it to \(format(threshold)) or below, "
                + "or run scripts/crap.sh baseline to add its row and then give the row a reason"
        case .worsened(let file, let name, let crap, let recorded, let tolerance):
            "worsened      \(file)  \(name)  crap \(format(crap)) > baseline \(format(recorded)) + tolerance \(format(tolerance)); "
                + "test or simplify it back down to \(format(recorded + tolerance)) or below, "
                + "or, as a last resort, raise its crap in the baseline by hand and say why in its reason "
                + "(scripts/crap.sh baseline never raises a score)"
        case .stale(let file, let name, let recorded, let reason):
            "stale         \(file)  \(name)  baseline records \(format(recorded)) but \(reason.explanation); "
                + "delete its line from the baseline or rerun scripts/crap.sh baseline"
        case .improved(let file, let name, let crap, let recorded):
            "improved      \(file)  \(name)  crap \(format(crap)) < baseline \(format(recorded)); "
                + "rerun scripts/crap.sh baseline to bank it"
        case .unexplained(let file, let name):
            "unexplained   \(file)  \(name)  baseline row has no reason; "
                + "write why it stays above the threshold in its reason column"
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
            if entry.reason.trimmingCharacters(in: .whitespaces).isEmpty {
                findings.append(.unexplained(file: entry.file, name: entry.name))
            }
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
    public static let header = "file\tname\tcrap\treason"

    /// Reads a baseline. A row is `file`, `name`, `crap`, and an optional `reason`; a file written
    /// before the reason column existed still parses.
    public static func parse(text: String) -> [BaselineEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard !line.hasPrefix("file\tname\tcrap") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 || fields.count == 4, let crap = Double(fields[2]) else { return nil }
            let reason = fields.count == 4 ? String(fields[3]) : ""
            return BaselineEntry(file: String(fields[0]), name: String(fields[1]), crap: crap, reason: reason)
        }
    }

    /// Renders every measured function above the threshold, keeping the reason a prior baseline
    /// recorded for a row that is still above it. A prior row keeps its recorded score when the
    /// function scores higher now, so a rewrite never hides a worsened function.
    public static func render(report: Report, threshold: Double, carrying prior: [BaselineEntry] = []) -> String {
        let priorRows = Dictionary(prior.map { ($0.file + "\t" + $0.name, $0) }, uniquingKeysWith: { _, last in last })
        let entries =
            report.functions
            .filter { ($0.crap ?? 0) > threshold }
            .sorted { ($0.file, $0.name) < ($1.file, $1.name) }
            .map { row in
                let recorded = priorRows[row.file + "\t" + row.name]
                let crap = min(row.crap ?? 0, recorded?.crap ?? .infinity)
                return "\(row.file)\t\(row.name)\t\(String(format: "%.1f", crap))\t\(recorded?.reason ?? "")"
            }
        return ([header] + entries).joined(separator: "\n") + "\n"
    }
}

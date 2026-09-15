import ArgumentParser
import CRAPKit
import Foundation

@main
struct Crap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crap",
        abstract: "Score Swift functions by CRAP = cc^2 * (1 - coverage)^3 + cc.",
        subcommands: [Measure.self, GateCommand.self, BaselineCommand.self],
        defaultSubcommand: Measure.self
    )
}

struct Measure: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Scan sources, join llvm-cov line coverage, and print the worst functions."
    )

    @Option(help: "Repository root that relative paths are resolved against.") var root: String
    @Option(help: "lcov file exported by llvm-cov.") var lcov: String
    @Option(name: .customLong("source"), parsing: .singleValue, help: "Source directory to scan, relative to root.")
    var sources: [String] = []
    @Option(name: .customLong("exclude"), parsing: .singleValue, help: "Glob of relative paths to skip.")
    var excludes: [String] = []
    @Option(help: "CRAP score a function must stay at or below.") var threshold: Double = 6
    @Option(help: "Write the full report as JSON to this path.") var json: String?
    @Option(help: "How many rows to print.") var top: Int = 25

    func run() throws {
        let root = URL(fileURLWithPath: root).standardizedFileURL.path
        let text = try readFile(lcov)
        let coverage = SourceScan.relativizeCoverage(LCOV.parse(text: text), root: root)
        let files = SourceScan.swiftFiles(root: root, sources: sources, excludes: excludes)
        var scanned: [ScannedFunction] = []
        for file in files {
            let source = try readFile(URL(fileURLWithPath: root).appendingPathComponent(file).path)
            scanned.append(contentsOf: SwiftFunctionScanner.scan(source: source, file: file))
        }

        var report = Scorer.score(scanned: scanned, coverage: coverage, threshold: threshold)
        report.sources = sources
        report.excludes = excludes

        print(Table.render(rows: report.functions.filter(\.isMeasured).prefix(top)))
        print(totalsLine(report.totals))
        print("unmeasured: \(report.totals.unmeasured) functions with no instrumented lines")

        if let json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = URL(fileURLWithPath: json)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(report).write(to: url)
        }
    }

    private func totalsLine(_ totals: Totals) -> String {
        let percent =
            totals.linesInstrumented > 0
            ? Double(totals.linesCovered) / Double(totals.linesInstrumented) * 100 : 0
        return
            "totals: \(totals.functions) functions, \(totals.measured) measured, "
            + "\(totals.aboveThreshold) above threshold \(String(format: "%.1f", threshold)), "
            + "max crap \(String(format: "%.1f", totals.maxCrap)), "
            + "lines \(totals.linesCovered)/\(totals.linesInstrumented) (\(String(format: "%.1f", percent))%)"
    }
}

struct GateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gate",
        abstract: "Compare a report against the baseline and fail on new or worsened violations."
    )

    @Option(help: "JSON report written by `crap measure --json`.") var report: String
    @Option(help: "Baseline TSV.") var baseline: String
    @Option(help: "CRAP score a function must stay at or below.") var threshold: Double = 6
    @Option(help: "Slack allowed before a baselined function counts as worsened.") var tolerance: Double = 0.5

    func run() throws {
        let decoded = try JSONDecoder().decode(Report.self, from: Data(contentsOf: URL(fileURLWithPath: report)))
        let entries = Baseline.parse(text: try readFile(baseline))
        let outcome = Gate.evaluate(
            report: decoded,
            baseline: entries,
            threshold: threshold,
            tolerance: tolerance
        )
        for finding in outcome.failures {
            print(finding.message)
        }
        for finding in outcome.notes {
            print("note: " + finding.message)
        }
        guard outcome.isClean else {
            throw ExitCode(outcome.exitCode)
        }
        print("crap gate clean: \(entries.count) baselined functions, threshold \(String(format: "%.1f", threshold))")
    }
}

struct BaselineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline",
        abstract: "Write every measured function above the threshold to a TSV baseline."
    )

    @Option(help: "JSON report written by `crap measure --json`.") var report: String
    @Option(help: "Path to write the baseline TSV to.") var write: String
    @Option(help: "CRAP score a function must stay at or below.") var threshold: Double = 6

    func run() throws {
        let decoded = try JSONDecoder().decode(Report.self, from: Data(contentsOf: URL(fileURLWithPath: report)))
        let prior = (try? String(contentsOfFile: write, encoding: .utf8)).map(Baseline.parse(text:)) ?? []
        let text = Baseline.render(report: decoded, threshold: threshold, carrying: prior)
        try text.write(to: URL(fileURLWithPath: write), atomically: true, encoding: .utf8)
        print("wrote \(text.split(separator: "\n").count - 1) baselined functions to \(write)")
    }
}

enum Table {
    static func render(rows: some Collection<FunctionRow>) -> String {
        let header = ["file", "name", "cc", "cov%", "crap"]
        let body = rows.map { row in
            [
                row.file,
                row.name,
                String(row.cc),
                String(format: "%.0f", (row.coverage ?? 0) * 100),
                String(format: "%.1f", row.crap ?? 0)
            ]
        }
        let widths = ([header] + body).reduce(into: [Int](repeating: 0, count: header.count)) { widths, columns in
            for (index, column) in columns.enumerated() {
                widths[index] = max(widths[index], column.count)
            }
        }
        return ([header] + body)
            .map { columns in
                columns.enumerated()
                    .map { index, column in
                        index < 2
                            ? column.padding(toLength: widths[index], withPad: " ", startingAt: 0)
                            : String(repeating: " ", count: widths[index] - column.count) + column
                    }
                    .joined(separator: "  ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }
}

func readFile(_ path: String) throws -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        throw ValidationError("cannot read \(path)")
    }
    return text
}

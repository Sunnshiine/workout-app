import Foundation

public enum FunctionKind: String, Codable, Sendable {
    case function
    case initializer
    case deinitializer
    case subscriptGetter
    case subscriptSetter
    case getter
    case setter
    case willSet
    case didSet
    case unknownAccessor
}

public struct FunctionRow: Codable, Sendable, Equatable {
    public var file: String
    public var name: String
    public var kind: FunctionKind
    public var startLine: Int
    public var endLine: Int
    public var cc: Int
    public var linesInstrumented: Int
    public var linesCovered: Int
    public var coverage: Double?
    public var crap: Double?

    public init(
        file: String,
        name: String,
        kind: FunctionKind,
        startLine: Int,
        endLine: Int,
        cc: Int,
        linesInstrumented: Int,
        linesCovered: Int,
        coverage: Double?,
        crap: Double?
    ) {
        self.file = file
        self.name = name
        self.kind = kind
        self.startLine = startLine
        self.endLine = endLine
        self.cc = cc
        self.linesInstrumented = linesInstrumented
        self.linesCovered = linesCovered
        self.coverage = coverage
        self.crap = crap
    }

    public var isMeasured: Bool { linesInstrumented > 0 }
}

public struct Totals: Codable, Sendable, Equatable {
    public var functions: Int
    public var measured: Int
    public var unmeasured: Int
    public var aboveThreshold: Int
    public var maxCrap: Double
    public var linesInstrumented: Int
    public var linesCovered: Int

    public init(
        functions: Int,
        measured: Int,
        unmeasured: Int,
        aboveThreshold: Int,
        maxCrap: Double,
        linesInstrumented: Int,
        linesCovered: Int
    ) {
        self.functions = functions
        self.measured = measured
        self.unmeasured = unmeasured
        self.aboveThreshold = aboveThreshold
        self.maxCrap = maxCrap
        self.linesInstrumented = linesInstrumented
        self.linesCovered = linesCovered
    }
}

public struct Report: Codable, Sendable {
    public var generatedAt: String
    public var threshold: Double
    public var sources: [String]
    public var excludes: [String]
    public var totals: Totals
    public var functions: [FunctionRow]

    public init(
        generatedAt: String,
        threshold: Double,
        sources: [String],
        excludes: [String],
        totals: Totals,
        functions: [FunctionRow]
    ) {
        self.generatedAt = generatedAt
        self.threshold = threshold
        self.sources = sources
        self.excludes = excludes
        self.totals = totals
        self.functions = functions
    }
}

public func crapScore(cc: Int, coverage: Double) -> Double {
    let uncovered = 1.0 - coverage
    return Double(cc * cc) * uncovered * uncovered * uncovered + Double(cc)
}

public func roundedToOneDecimal(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

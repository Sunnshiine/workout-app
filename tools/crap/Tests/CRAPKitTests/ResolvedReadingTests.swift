import Testing

@testable import CRAPKit

/// The readings documented under "Readings the rules above do not state" in README.md.
@Suite struct ResolvedReadingTests {
    @Test func whileConditionListFollowsTheIfRule() {
        let source = "func f(_ a: Bool) { while a, let b = Optional(1), b > 0 { break } }"
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned[0].cc == 4)
    }

    @Test func unknownAccessorsAreNamedByTheirSpecifier() {
        let source = """
            struct A {
                var s = 0
                var x: Int {
                    _read { yield s }
                }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.map(\.name) == ["A.x._read"])
        #expect(scanned.map(\.kind) == [.unknownAccessor])
    }

    @Test func typeLevelInitializerExpressionsAreNotRowsAndDoNotChargeANeighbour() {
        let source = """
            struct A {
                static let handler: (Int) -> Int = { $0 > 0 ? 1 : 2 }
                func f() { print(1) }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.map(\.name) == ["A.f()"])
        #expect(scanned[0].cc == 1)
    }

    @Test func typesNestedInAFunctionKeepAPositionalChain() {
        let source = """
            func outer() {
                struct Local {
                    func f() { print(1) }
                }
                print(Local().f())
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.map(\.name).sorted() == ["outer()", "outer().Local.f()"])
        #expect(scanned.first { $0.name == "outer()" }?.nestedSpans == [3...3])
    }

    @Test func explicitAccessorsSpanOnlyThemselves() {
        let source = """
            struct A {
                var s = 0
                var x: Int {
                    get { s }
                    set { s = newValue }
                }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.first { $0.name == "A.x.get" }.map { $0.startLine...$0.endLine } == 4...4)
        #expect(scanned.first { $0.name == "A.x.set" }.map { $0.startLine...$0.endLine } == 5...5)
    }

    @Test func implicitGetterSpansTheWholeDeclaration() {
        let source = """
            struct A {
                var x: Int {
                    1
                }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.first { $0.name == "A.x.get" }.map { $0.startLine...$0.endLine } == 2...4)
    }

    @Test func bothBranchesOfAnIfConfigAreRows() {
        let source = """
            struct A {
                #if canImport(UIKit)
                    func play() { print(1) }
                #else
                    func play() { print(2) }
                #endif
            }
            """
        #expect(SwiftFunctionScanner.scan(source: source, file: "T.swift").map(\.name) == ["A.play()@1", "A.play()@2"])
    }
}

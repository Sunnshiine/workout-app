import Testing

@testable import CRAPKit

private func complexity(_ source: String, _ name: String = "f(_:)") -> Int {
    let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
    guard let match = scanned.first(where: { $0.name == name }) else {
        Issue.record("no function named \(name) in \(scanned.map(\.name))")
        return -1
    }
    return match.cc
}

@Suite struct ComplexityTests {
    @Test func plainFunctionIsOne() {
        #expect(complexity("func f(_ a: Int) { print(a) }") == 1)
    }

    @Test func ifAddsOne() {
        #expect(complexity("func f(_ a: Int) { if a > 0 { print(a) } }") == 2)
    }

    @Test func elseAloneAddsNothing() {
        #expect(complexity("func f(_ a: Int) { if a > 0 { print(a) } else { print(0) } }") == 2)
    }

    @Test func elseIfAddsOne() {
        #expect(complexity("func f(_ a: Int) { if a > 0 { } else if a > 1 { } else { } }") == 3)
    }

    @Test func guardAddsOne() {
        #expect(complexity("func f(_ a: Int?) { guard a != nil else { return } }") == 2)
    }

    @Test func extraConditionsAddOneEach() {
        #expect(complexity("func f(_ a: Bool) { if a, let b = Optional(1), b > 0 { } }") == 4)
    }

    @Test func forAddsOne() {
        #expect(complexity("func f(_ a: [Int]) { for x in a { print(x) } }") == 2)
    }

    @Test func forWhereAddsTwo() {
        #expect(complexity("func f(_ a: [Int]) { for x in a where x > 0 { print(x) } }") == 3)
    }

    @Test func whileAddsOne() {
        #expect(complexity("func f(_ a: Int) { var i = a; while i > 0 { i -= 1 } }") == 2)
    }

    @Test func repeatAddsOne() {
        #expect(complexity("func f(_ a: Int) { var i = a; repeat { i -= 1 } while i > 0 }") == 2)
    }

    @Test func eachCaseAddsOneAndDefaultAddsNothing() {
        let source = """
            func f(_ a: Int) {
                switch a {
                case 1: break
                case 2, 3: break
                default: break
                }
            }
            """
        #expect(complexity(source) == 3)
    }

    @Test func caseWhereAddsOne() {
        let source = """
            func f(_ a: Int) {
                switch a {
                case let x where x > 0: print(x)
                default: break
                }
            }
            """
        #expect(complexity(source) == 3)
    }

    @Test func eachCatchAddsOne() {
        let source = """
            func f(_ a: Int) {
                do { try g(a) } catch is CancellationError { } catch { }
            }
            """
        #expect(complexity(source) == 3)
    }

    @Test func logicalOperatorsAddOneEach() {
        #expect(complexity("func f(_ a: Bool) { let x = a && !a || a; print(x) }") == 3)
    }

    @Test func ternaryAddsOne() {
        #expect(complexity("func f(_ a: Bool) { print(a ? 1 : 2) }") == 2)
    }

    @Test func nilCoalescingAddsOne() {
        #expect(complexity("func f(_ a: Int?) { print(a ?? 0) }") == 2)
    }

    @Test func closuresCountTowardTheEnclosingDeclaration() {
        let source = """
            struct A {
                func f(_ a: [Int]) {
                    a.forEach { print($0 > 0 ? 1 : 2) }
                }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.map(\.name) == ["A.f(_:)"])
        #expect(scanned[0].cc == 2)
    }

    @Test func nestedFunctionsAreSeparateRows() {
        let source = """
            func f(_ a: Int) {
                func inner(_ b: Int) -> Int { b > 0 ? 1 : 2 }
                print(inner(a))
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.first { $0.name == "f(_:)" }?.cc == 1)
        #expect(scanned.first { $0.name == "f(_:).inner(_:)" }?.cc == 2)
    }

    @Test func uncountedConstructsAddNothing() {
        let source = """
            func f(_ a: Int?) throws {
                defer { print("done") }
                do {
                    let value = try g(a)
                    _ = try? g(a)
                    _ = a?.description
                    if false { throw CancellationError() }
                    return
                }
            }
            """
        // The only counting construct here is the `if`.
        #expect(complexity(source) == 2)
    }

    @Test func combinedSnippet() {
        let source = """
            func f(_ items: [Int]?, flag: Bool) -> Int {
                guard let items, !items.isEmpty else { return 0 }
                var total = 0
                for item in items where item > 0 {
                    switch item {
                    case 1, 2: total += item
                    case let other where other > 10: total += other
                    default: total += flag ? 1 : 0
                    }
                }
                return total
            }
            """
        // 1 base + 2 guard conditions + 2 for/where + 1 case + 2 case/where + 1 ternary
        #expect(complexity(source, "f(_:flag:)") == 9)
    }
}

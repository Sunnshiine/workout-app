import Testing

@testable import CRAPKit

private func names(_ source: String) -> [String] {
    SwiftFunctionScanner.scan(source: source, file: "T.swift").map(\.name)
}

@Suite struct IdentityTests {
    @Test func methodInAStruct() {
        #expect(names("struct A { func m(_ x: Int, y: Int) { print(x, y) } }") == ["A.m(_:y:)"])
    }

    @Test func methodInAnExtensionUsesTheExtendedTypeWithoutGenerics() {
        #expect(names("extension Array<Int> { func m() { } }") == ["Array.m()"])
    }

    @Test func initializer() {
        #expect(names("struct A { let x: Int; init(a: Int) { x = a } }") == ["A.init(a:)"])
    }

    @Test func deinitializer() {
        #expect(names("class A { deinit { print(1) } }") == ["A.deinit"])
    }

    @Test func implicitGetter() {
        #expect(names("struct A { var x: Int { 1 } }") == ["A.x.get"])
    }

    @Test func getterAndSetterPair() {
        let source = """
            struct A {
                var storage = 0
                var x: Int {
                    get { storage }
                    set { storage = newValue }
                }
            }
            """
        #expect(names(source) == ["A.x.get", "A.x.set"])
    }

    @Test func observersAreRows() {
        let source = """
            struct A {
                var x: Int = 0 {
                    willSet { print(newValue) }
                    didSet { print(oldValue) }
                }
            }
            """
        #expect(names(source) == ["A.x.willSet", "A.x.didSet"])
    }

    @Test func subscriptAccessors() {
        let source = """
            struct A {
                subscript(index: Int) -> Int {
                    get { index }
                    set { print(newValue) }
                }
            }
            """
        #expect(names(source) == ["A.subscript(_:).get", "A.subscript(_:).set"])
    }

    @Test func subscriptKeepsExplicitArgumentLabels() {
        let source = "struct A { subscript(at index: Int) -> Int { index } }"
        #expect(names(source) == ["A.subscript(at:).get"])
    }

    @Test func nestedTypes() {
        #expect(names("struct A { struct B { func f() { } } }") == ["A.B.f()"])
    }

    @Test func topLevelFunctionHasNoChain() {
        #expect(names("func f(_ a: Int) { print(a) }") == ["f(_:)"])
    }

    @Test func nestedLocalFunctionIsExcludedFromTheParentSpan() {
        let source = """
            func outer(_ a: Int) {
                func inner(_ b: Int) -> Int {
                    b + 1
                }
                print(inner(a))
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        let outer = scanned.first { $0.name == "outer(_:)" }
        let inner = scanned.first { $0.name == "outer(_:).inner(_:)" }
        #expect(inner?.startLine == 2)
        #expect(inner?.endLine == 4)
        #expect(outer?.startLine == 1)
        #expect(outer?.endLine == 6)
        #expect(outer?.nestedSpans == [2...4])
        #expect(outer?.ownedLines().sorted() == [1, 5, 6])
    }

    @Test func operatorKeepsItsSpelling() {
        let source = "struct A { static func == (lhs: A, rhs: A) -> Bool { true } }"
        #expect(names(source) == ["A.==(_:_:)"])
    }

    @Test func overloadsAreNumberedInSourceOrder() {
        let source = """
            struct A {
                func f(_ x: Int) { print(x) }
                func f(_ x: String) { print(x) }
            }
            """
        #expect(names(source) == ["A.f(_:)@1", "A.f(_:)@2"])
    }

    @Test func declarationsWithoutBodiesAreNotRows() {
        let source = """
            protocol P {
                func f()
                var x: Int { get set }
            }
            struct A: P {
                var stored = 0
                func f() { print(stored) }
                var x: Int { get { stored } set { stored = newValue } }
            }
            """
        #expect(names(source) == ["A.f()", "A.x.get", "A.x.set"])
    }

    @Test func kindsAreClassified() {
        let source = """
            struct A {
                var s = 0
                init() { }
                func f() { }
                var x: Int { get { s } set { s = newValue } }
                subscript(i: Int) -> Int { i }
            }
            """
        let scanned = SwiftFunctionScanner.scan(source: source, file: "T.swift")
        #expect(scanned.map(\.kind) == [.initializer, .function, .getter, .setter, .subscriptGetter])
    }
}

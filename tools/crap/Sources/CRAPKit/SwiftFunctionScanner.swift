import Foundation
import SwiftParser
import SwiftSyntax

public struct ScannedFunction: Sendable, Equatable {
    public var file: String
    public var name: String
    public var kind: FunctionKind
    public var startLine: Int
    public var endLine: Int
    public var cc: Int
    public var nestedSpans: [ClosedRange<Int>]

    public init(
        file: String,
        name: String,
        kind: FunctionKind,
        startLine: Int,
        endLine: Int,
        cc: Int,
        nestedSpans: [ClosedRange<Int>]
    ) {
        self.file = file
        self.name = name
        self.kind = kind
        self.startLine = startLine
        self.endLine = endLine
        self.cc = cc
        self.nestedSpans = nestedSpans
    }

    /// Lines the row owns: its own span minus the spans of declarations nested inside it.
    public func ownedLines() -> Set<Int> {
        var lines = Set(startLine...endLine)
        for span in nestedSpans {
            lines.subtract(span)
        }
        return lines
    }
}

public enum SwiftFunctionScanner {
    public static func scan(source: String, file: String) -> [ScannedFunction] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = FunctionVisitor(file: file, converter: converter)
        visitor.walk(tree)
        return disambiguate(visitor.finished.sorted { $0.startLine < $1.startLine })
    }

    /// Same qualified name twice in one file (overloads) gets a 1-based `@n` suffix on every member of the group.
    private static func disambiguate(_ functions: [ScannedFunction]) -> [ScannedFunction] {
        var counts: [String: Int] = [:]
        for function in functions {
            counts[function.name, default: 0] += 1
        }
        var seen: [String: Int] = [:]
        return functions.map { function in
            guard counts[function.name, default: 0] > 1 else { return function }
            let index = seen[function.name, default: 0] + 1
            seen[function.name] = index
            var copy = function
            copy.name = "\(function.name)@\(index)"
            return copy
        }
    }
}

private struct OpenDecl {
    var name: String
    var kind: FunctionKind
    var startLine: Int
    var endLine: Int
    var cc: Int
    var nested: [ClosedRange<Int>]
}

private enum Frame {
    case none
    case name
    case decl
    case property
}

private struct PropertyContext {
    var base: String
    var isSubscript: Bool
}

private final class FunctionVisitor: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var finished: [ScannedFunction] = []

    private var nameStack: [String] = []
    private var open: [OpenDecl] = []
    private var properties: [PropertyContext] = []
    private var frames: [Frame] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Scope bookkeeping

    private func line(_ position: AbsolutePosition) -> Int {
        converter.location(for: position).line
    }

    private func span(_ node: some SyntaxProtocol) -> (Int, Int) {
        (line(node.positionAfterSkippingLeadingTrivia), line(node.endPositionBeforeTrailingTrivia))
    }

    private func qualified(_ component: String) -> String {
        nameStack.isEmpty ? component : nameStack.joined(separator: ".") + "." + component
    }

    private func pushName(_ component: String) -> SyntaxVisitorContinueKind {
        nameStack.append(component)
        frames.append(.name)
        return .visitChildren
    }

    private func pushDecl(
        component: String,
        kind: FunctionKind,
        node: some SyntaxProtocol
    ) -> SyntaxVisitorContinueKind {
        let (start, end) = span(node)
        open.append(OpenDecl(name: qualified(component), kind: kind, startLine: start, endLine: end, cc: 1, nested: []))
        nameStack.append(component)
        frames.append(.decl)
        return .visitChildren
    }

    private func pushNone() -> SyntaxVisitorContinueKind {
        frames.append(.none)
        return .visitChildren
    }

    private func pop() {
        switch frames.removeLast() {
        case .none:
            break
        case .name:
            nameStack.removeLast()
        case .property:
            properties.removeLast()
        case .decl:
            let decl = open.removeLast()
            nameStack.removeLast()
            if !open.isEmpty {
                open[open.count - 1].nested.append(decl.startLine...decl.endLine)
            }
            finished.append(
                ScannedFunction(
                    file: file,
                    name: decl.name,
                    kind: decl.kind,
                    startLine: decl.startLine,
                    endLine: decl.endLine,
                    cc: decl.cc,
                    nestedSpans: decl.nested
                )
            )
        }
    }

    private func bump(_ amount: Int) {
        guard !open.isEmpty, amount > 0 else { return }
        open[open.count - 1].cc += amount
    }

    // MARK: - Type scopes

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { pushName(node.name.text) }
    override func visitPost(_ node: StructDeclSyntax) { pop() }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { pushName(node.name.text) }
    override func visitPost(_ node: ClassDeclSyntax) { pop() }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { pushName(node.name.text) }
    override func visitPost(_ node: EnumDeclSyntax) { pop() }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { pushName(node.name.text) }
    override func visitPost(_ node: ActorDeclSyntax) { pop() }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { pushName(node.name.text) }
    override func visitPost(_ node: ProtocolDeclSyntax) { pop() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushName(Self.typeName(node.extendedType))
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { pop() }

    private static func typeName(_ type: TypeSyntax) -> String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return typeName(member.baseType) + "." + member.name.text
        }
        return type.trimmedDescription
    }

    // MARK: - Declarations with bodies

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else {
            frames.append(.none)
            return .skipChildren
        }
        let isOperator = node.name.tokenKind != .identifier(node.name.text)
        let labels = Self.callLabels(node.signature.parameterClause, labelsByDefault: !isOperator)
        return pushDecl(component: "\(node.name.text)(\(labels))", kind: .function, node: node)
    }
    override func visitPost(_ node: FunctionDeclSyntax) { pop() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else {
            frames.append(.none)
            return .skipChildren
        }
        let labels = Self.callLabels(node.signature.parameterClause, labelsByDefault: true)
        return pushDecl(component: "init(\(labels))", kind: .initializer, node: node)
    }
    override func visitPost(_ node: InitializerDeclSyntax) { pop() }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else {
            frames.append(.none)
            return .skipChildren
        }
        return pushDecl(component: "deinit", kind: .deinitializer, node: node)
    }
    override func visitPost(_ node: DeinitializerDeclSyntax) { pop() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindings.count == 1,
            let binding = node.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            let block = binding.accessorBlock
        else {
            return pushNone()
        }
        switch block.accessors {
        case .getter:
            return pushDecl(component: "\(identifier).get", kind: .getter, node: node)
        case .accessors:
            properties.append(PropertyContext(base: identifier, isSubscript: false))
            frames.append(.property)
            return .visitChildren
        }
    }
    override func visitPost(_ node: VariableDeclSyntax) { pop() }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let labels = Self.callLabels(node.parameterClause, labelsByDefault: false)
        let base = "subscript(\(labels))"
        guard let block = node.accessorBlock else { return pushNone() }
        switch block.accessors {
        case .getter:
            return pushDecl(component: "\(base).get", kind: .subscriptGetter, node: node)
        case .accessors:
            properties.append(PropertyContext(base: base, isSubscript: true))
            frames.append(.property)
            return .visitChildren
        }
    }
    override func visitPost(_ node: SubscriptDeclSyntax) { pop() }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil, let property = properties.last else {
            frames.append(.none)
            return node.body == nil ? .skipChildren : .visitChildren
        }
        let specifier = node.accessorSpecifier.text
        let kind: FunctionKind =
            switch specifier {
            case "get": property.isSubscript ? .subscriptGetter : .getter
            case "set": property.isSubscript ? .subscriptSetter : .setter
            case "willSet": .willSet
            case "didSet": .didSet
            default: .unknownAccessor
            }
        return pushDecl(component: "\(property.base).\(specifier)", kind: kind, node: node)
    }
    override func visitPost(_ node: AccessorDeclSyntax) { pop() }

    /// Functions label a parameter with its first name; subscripts and operators only when a second
    /// (internal) name is present, because neither takes an argument label at the call site by default.
    private static func callLabels(_ clause: FunctionParameterClauseSyntax, labelsByDefault: Bool) -> String {
        clause.parameters
            .map { parameter in
                let label = labelsByDefault || parameter.secondName != nil ? parameter.firstName.text : "_"
                return "\(label):"
            }
            .joined()
    }

    // MARK: - Cyclomatic complexity

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        bump(node.conditions.count)
        return .visitChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node.conditions.count)
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node.conditions.count)
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(1)
        return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node.whereClause == nil ? 1 : 2)
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        guard case .case(let label) = node.label else { return .visitChildren }
        bump(1 + label.caseItems.count { $0.whereClause != nil })
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        bump(1)
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if ["&&", "||", "??"].contains(node.operator.text) {
            bump(1)
        }
        return .visitChildren
    }

    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        bump(1)
        return .visitChildren
    }

    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        bump(1)
        return .visitChildren
    }
}

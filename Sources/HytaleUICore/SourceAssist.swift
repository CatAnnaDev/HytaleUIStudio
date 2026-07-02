import Foundation

public struct CompletionItem: Equatable, Sendable {
    public enum Kind: Sendable {
        case widget
        case property
        case field
        case enumValue
        case keyword
        case reference
        case constructor
        case snippet
    }
    public var insertText: String
    public var label: String
    public var detail: String
    public var kind: Kind

    public init(insertText: String, label: String, detail: String, kind: Kind) {
        self.insertText = insertText
        self.label = label
        self.detail = detail
        self.kind = kind
    }
}

public struct CompletionResult: Sendable {
    public var replaceStart: Int
    public var replaceEnd: Int
    public var items: [CompletionItem]

    public init(replaceStart: Int, replaceEnd: Int, items: [CompletionItem]) {
        self.replaceStart = replaceStart
        self.replaceEnd = replaceEnd
        self.items = items
    }
}

public enum SourceAssist {
    private static let allPropertyNames: [String] = {
        var set = Set<String>()
        for properties in CorpusCatalog.widgetProperties.values { set.formUnion(properties) }
        set.formUnion(CorpusCatalog.propertyKind.keys)
        return set.sorted()
    }()

    private static let allFieldNames: [String] = {
        var set = Set<String>()
        for fields in CorpusCatalog.recordFields.values { set.formUnion(fields) }
        return set.sorted()
    }()

    public static func complete(source: String, cursor: Int, moduleMembers: (String) -> [String] = { _ in [] }) -> CompletionResult {
        let scalars = Array(source)
        let clampedCursor = max(0, min(cursor, scalars.count))

        var wordStart = clampedCursor
        while wordStart > 0, isWordChar(scalars[wordStart - 1]) {
            wordStart -= 1
        }
        var sigil: Character? = nil
        if wordStart > 0, "@$#%".contains(scalars[wordStart - 1]) {
            sigil = scalars[wordStart - 1]
            wordStart -= 1
        }
        let prefix = String(scalars[wordStart..<clampedCursor])

        let context = analyze(source: source, wordStart: wordStart)
        let document = Parser.parse(source).document
        let localDefs = document.statements.compactMap { statement -> String? in
            if case .definition(let definition) = statement { return definition.name } else { return nil }
        }
        let imports = document.statements.compactMap { statement -> String? in
            if case .importDeclaration(let declaration) = statement { return declaration.variable } else { return nil }
        }

        var items: [CompletionItem]
        if let sigil, sigil == "@" {
            items = localDefs.map { CompletionItem(insertText: "@\($0)", label: "@\($0)", detail: "definition", kind: .reference) }
        } else if let sigil, sigil == "$" {
            items = imports.map { CompletionItem(insertText: "$\($0)", label: "$\($0)", detail: "import", kind: .reference) }
        } else {
            switch context.kind {
            case .moduleMember:
                items = moduleMembers(context.name ?? "").map {
                    CompletionItem(insertText: "@\($0)", label: "@\($0)", detail: "$\(context.name ?? "").\($0)", kind: .reference)
                }
            case .value:
                items = valueCandidates(field: context.name, localDefs: localDefs, imports: imports)
            case .recordField:
                items = recordFieldCandidates(owner: context.name)
            case .member:
                let container: Bool
                if let widget = context.name, !widget.isEmpty {
                    container = SemanticCatalog.isContainer(widget)
                } else {
                    container = true
                }
                items = memberCandidates(widget: context.name, topLevel: context.topLevel, container: container)
            }
        }

        let lowerPrefix = prefix.lowercased()
        let filtered = items.filter { item in
            lowerPrefix.isEmpty || item.insertText.lowercased().hasPrefix(lowerPrefix) || item.label.lowercased().hasPrefix(lowerPrefix)
        }
        return CompletionResult(replaceStart: wordStart, replaceEnd: clampedCursor, items: Array(filtered.prefix(120)))
    }

    private struct Context {
        enum Kind { case member, value, recordField, moduleMember }
        var kind: Kind
        var name: String?
        var topLevel: Bool
    }

    private static func analyze(source: String, wordStart: Int) -> Context {
        var lexer = Lexer(source)
        let tokens = lexer.tokenize().filter { $0.kind != .endOfFile && $0.range.end.offset <= wordStart }

        var braceStack: [String] = []
        var parenStack: [String] = []
        var previous: Token? = nil
        var beforePrevious: Token? = nil

        for token in tokens {
            switch token.kind {
            case .leftBrace:
                braceStack.append(headName(previous: previous, beforePrevious: beforePrevious))
            case .rightBrace:
                if !braceStack.isEmpty { braceStack.removeLast() }
            case .leftParen:
                parenStack.append(ownerName(previous: previous, beforePrevious: beforePrevious, parenTop: parenStack.last))
            case .rightParen:
                if !parenStack.isEmpty { parenStack.removeLast() }
            default:
                break
            }
            beforePrevious = previous
            previous = token
        }

        if previous?.kind == .dot, beforePrevious?.kind == .moduleRef {
            return Context(kind: .moduleMember, name: beforePrevious?.text, topLevel: braceStack.isEmpty)
        }
        if previous?.kind == .colon || previous?.kind == .equals {
            return Context(kind: .value, name: beforePrevious?.text, topLevel: braceStack.isEmpty)
        }
        if !parenStack.isEmpty, previous?.kind == .leftParen || previous?.kind == .comma {
            return Context(kind: .recordField, name: parenStack.last, topLevel: braceStack.isEmpty)
        }
        if !parenStack.isEmpty {
            return Context(kind: .recordField, name: parenStack.last, topLevel: braceStack.isEmpty)
        }
        return Context(kind: .member, name: braceStack.last, topLevel: braceStack.isEmpty)
    }

    private static func headName(previous: Token?, beforePrevious: Token?) -> String {
        guard let previous else { return "" }
        if previous.kind == .identifier { return previous.text }
        if previous.kind == .hash, beforePrevious?.kind == .identifier { return beforePrevious?.text ?? "" }
        return ""
    }

    private static func ownerName(previous: Token?, beforePrevious: Token?, parenTop: String?) -> String {
        guard let previous else { return parenTop ?? "" }
        if previous.kind == .colon || previous.kind == .equals {
            return beforePrevious?.text ?? ""
        }
        if previous.kind == .identifier {
            return previous.text
        }
        if previous.kind == .comma || previous.kind == .leftParen {
            return parenTop ?? ""
        }
        return parenTop ?? ""
    }

    private static func valueCandidates(field: String?, localDefs: [String], imports: [String]) -> [CompletionItem] {
        var items: [CompletionItem] = []
        if let field {
            for value in (CorpusCatalog.enumValues[field] ?? []) {
                items.append(CompletionItem(insertText: value, label: value, detail: "enum \(field)", kind: .enumValue))
            }
            switch CorpusCatalog.propertyKind[field] {
            case "bool":
                items.append(CompletionItem(insertText: "true", label: "true", detail: "boolean", kind: .keyword))
                items.append(CompletionItem(insertText: "false", label: "false", detail: "boolean", kind: .keyword))
            case "color":
                items.append(CompletionItem(insertText: "#ffffff", label: "#ffffff", detail: "color", kind: .snippet))
            case "record":
                items.append(CompletionItem(insertText: "(", label: "( … )", detail: "record", kind: .snippet))
            default:
                break
            }
            for constructor in (CorpusCatalog.propertyConstructors[field] ?? []) {
                items.append(CompletionItem(insertText: "\(constructor)(", label: "\(constructor)( … )", detail: "constructor", kind: .constructor))
            }
        }
        for def in localDefs {
            items.append(CompletionItem(insertText: "@\(def)", label: "@\(def)", detail: "definition", kind: .reference))
        }
        for variable in imports {
            items.append(CompletionItem(insertText: "$\(variable)", label: "$\(variable)", detail: "import", kind: .reference))
        }
        return items
    }

    private static func recordFieldCandidates(owner: String?) -> [CompletionItem] {
        let fields: [String]
        if let owner, let known = CorpusCatalog.recordFields[owner], !known.isEmpty {
            fields = known
        } else {
            fields = allFieldNames
        }
        return fields.map { field in
            CompletionItem(insertText: "\(field): ", label: field, detail: fieldDetail(field), kind: .field)
        }
    }

    private static func fieldDetail(_ field: String) -> String {
        CorpusCatalog.propertyKind[field] ?? "field"
    }

    private static func memberCandidates(widget: String?, topLevel: Bool, container: Bool) -> [CompletionItem] {
        var items: [CompletionItem] = []
        if topLevel {
            items.append(CompletionItem(insertText: "$Name = \"path.ui\";", label: "$import", detail: "import another .ui", kind: .snippet))
            items.append(CompletionItem(insertText: "@Name = ", label: "@definition", detail: "define a macro/style", kind: .snippet))
        } else {
            let properties: [String]
            if let widget, !widget.isEmpty, let known = CorpusCatalog.widgetProperties[widget], !known.isEmpty {
                properties = known
            } else {
                properties = allPropertyNames
            }
            for property in properties {
                items.append(CompletionItem(insertText: "\(property): ", label: property, detail: propertyDetail(property, widget: widget), kind: .property))
            }
        }
        if topLevel || container {
            for widgetName in CorpusCatalog.widgets {
                let summary = SemanticCatalog.widget(named: widgetName)?.summary ?? "widget"
                items.append(CompletionItem(insertText: widgetName, label: widgetName, detail: summary, kind: .widget))
            }
        }
        return items
    }

    private static func propertyDetail(_ property: String, widget: String?) -> String {
        CorpusCatalog.propertyKind[property] ?? "property"
    }

    private static func isWordChar(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}

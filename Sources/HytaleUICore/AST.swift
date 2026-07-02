import Foundation

public struct UIDocument: Sendable, Equatable {
    public var statements: [UIStatement]
    public var range: SourceRange

    public init(statements: [UIStatement], range: SourceRange = .unknown) {
        self.statements = statements
        self.range = range
    }

    public static func == (lhs: UIDocument, rhs: UIDocument) -> Bool {
        lhs.statements == rhs.statements
    }
}

public enum UIStatement: Sendable, Equatable {
    case importDeclaration(UIImport)
    case definition(UIDefinition)
    case element(UIElement)
}

public struct UIImport: Sendable, Equatable {
    public var variable: String
    public var path: String
    public var range: SourceRange

    public init(variable: String, path: String, range: SourceRange = .unknown) {
        self.variable = variable
        self.path = path
        self.range = range
    }

    public static func == (lhs: UIImport, rhs: UIImport) -> Bool {
        lhs.variable == rhs.variable && lhs.path == rhs.path
    }
}

public struct UIDefinition: Sendable, Equatable {
    public var name: String
    public var value: UIValue
    public var range: SourceRange

    public init(name: String, value: UIValue, range: SourceRange = .unknown) {
        self.name = name
        self.value = value
        self.range = range
    }

    public static func == (lhs: UIDefinition, rhs: UIDefinition) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value
    }
}

public enum UIElementType: Sendable, Equatable {
    case builtin(String)
    case component(UIReference)
    case slot

    public var displayName: String {
        switch self {
        case .builtin(let name): return name
        case .component(let reference): return reference.displayName
        case .slot: return ""
        }
    }
}

public struct UIElement: Sendable, Equatable {
    public var type: UIElementType
    public var id: String?
    public var members: [UIMember]
    public var range: SourceRange

    public init(type: UIElementType, id: String? = nil, members: [UIMember] = [], range: SourceRange = .unknown) {
        self.type = type
        self.id = id
        self.members = members
        self.range = range
    }

    public var properties: [UIProperty] {
        members.compactMap { if case .property(let property) = $0 { return property } else { return nil } }
    }

    public var parameters: [UIProperty] {
        members.compactMap { if case .parameter(let property) = $0 { return property } else { return nil } }
    }

    public var children: [UIElement] {
        members.compactMap { if case .child(let child) = $0 { return child } else { return nil } }
    }

    public func property(_ name: String) -> UIValue? {
        for member in members {
            if case .property(let property) = member, property.name == name {
                return property.value
            }
        }
        return nil
    }

    public static func == (lhs: UIElement, rhs: UIElement) -> Bool {
        lhs.type == rhs.type && lhs.id == rhs.id && lhs.members == rhs.members
    }
}

public struct UIProperty: Sendable, Equatable {
    public var name: String
    public var value: UIValue
    public var range: SourceRange

    public init(name: String, value: UIValue, range: SourceRange = .unknown) {
        self.name = name
        self.value = value
        self.range = range
    }

    public static func == (lhs: UIProperty, rhs: UIProperty) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value
    }
}

public enum UIMember: Sendable, Equatable {
    case property(UIProperty)
    case parameter(UIProperty)
    case child(UIElement)
}

public struct UIReference: Sendable, Equatable {
    public var module: String?
    public var name: String
    public var fields: [String]

    public init(module: String? = nil, name: String, fields: [String] = []) {
        self.module = module
        self.name = name
        self.fields = fields
    }

    public var displayName: String {
        var base = module != nil ? "$\(module!).@\(name)" : "@\(name)"
        for field in fields {
            base += ".\(field)"
        }
        return base
    }
}

public struct UIColor: Sendable, Equatable {
    public var hex: String
    public var alpha: Double?

    public init(hex: String, alpha: Double? = nil) {
        self.hex = hex
        self.alpha = alpha
    }
}

public enum UIUnaryOperator: String, Sendable, Equatable {
    case negate = "-"
    case identity = "+"
}

public enum UIBinaryOperator: String, Sendable, Equatable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
}

public struct UIRecordEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case field(name: String)
        case spread
    }

    public var kind: Kind
    public var value: UIValue
    public var range: SourceRange

    public init(kind: Kind, value: UIValue, range: SourceRange = .unknown) {
        self.kind = kind
        self.value = value
        self.range = range
    }

    public static func == (lhs: UIRecordEntry, rhs: UIRecordEntry) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value
    }
}

public struct UIRecord: Sendable, Equatable {
    public var entries: [UIRecordEntry]

    public init(entries: [UIRecordEntry] = []) {
        self.entries = entries
    }

    public func value(_ name: String) -> UIValue? {
        for entry in entries {
            if case .field(let entryName) = entry.kind, entryName == name {
                return entry.value
            }
        }
        return nil
    }
}

public indirect enum UIValue: Sendable, Equatable {
    case number(Double, isInteger: Bool)
    case string(String)
    case boolean(Bool)
    case color(UIColor)
    case identifier(String)
    case binding(String)
    case reference(UIReference)
    case record(UIRecord)
    case list([UIValue])
    case constructor(name: String, record: UIRecord)
    case element(UIElement)
    case unary(UIUnaryOperator, UIValue)
    case binary(UIBinaryOperator, lhs: UIValue, rhs: UIValue)
    case grouping(UIValue)
}

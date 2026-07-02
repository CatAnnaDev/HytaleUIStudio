import Foundation

public struct Serializer {
    public var indentUnit: String
    public var inlineWidthLimit: Int

    public init(indentUnit: String = "  ", inlineWidthLimit: Int = 80) {
        self.indentUnit = indentUnit
        self.inlineWidthLimit = inlineWidthLimit
    }

    public func serialize(_ document: UIDocument) -> String {
        var lines: [String] = []
        for (offset, statement) in document.statements.enumerated() {
            if offset > 0 { lines.append("") }
            lines.append(serialize(statement, indent: 0))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func serialize(_ statement: UIStatement, indent: Int) -> String {
        switch statement {
        case .importDeclaration(let declaration):
            return "$\(declaration.variable) = \"\(escape(declaration.path))\";"
        case .definition(let definition):
            return "@\(definition.name) = \(serialize(definition.value, indent: indent));"
        case .element(let element):
            return serialize(element, indent: indent)
        }
    }

    public func serialize(_ element: UIElement, indent: Int) -> String {
        let pad = String(repeating: indentUnit, count: indent)
        let childPad = String(repeating: indentUnit, count: indent + 1)
        var head = element.type.displayName
        if let id = element.id {
            head = head.isEmpty ? "#\(id)" : "\(head) #\(id)"
        }
        if element.members.isEmpty {
            return "\(head) {}"
        }
        var lines: [String] = ["\(head) {"]
        for member in element.members {
            lines.append(childPad + serialize(member, indent: indent + 1))
        }
        lines.append(pad + "}")
        return lines.joined(separator: "\n")
    }

    public func serialize(_ member: UIMember, indent: Int) -> String {
        switch member {
        case .property(let property):
            return "\(property.name): \(serialize(property.value, indent: indent));"
        case .parameter(let property):
            return "@\(property.name) = \(serialize(property.value, indent: indent));"
        case .child(let element):
            return serialize(element, indent: indent)
        }
    }

    public func serialize(_ value: UIValue, indent: Int) -> String {
        if let inline = inlineValue(value), inline.count <= inlineWidthLimit {
            return inline
        }
        switch value {
        case .record(let record):
            return multilineRecord(name: nil, record: record, indent: indent)
        case .constructor(let name, let record):
            return multilineRecord(name: name, record: record, indent: indent)
        case .list(let items):
            return multilineList(items, indent: indent)
        case .element(let element):
            return serialize(element, indent: indent)
        case .grouping(let inner):
            return "(" + serialize(inner, indent: indent) + ")"
        default:
            return inlineValue(value) ?? ""
        }
    }

    private func multilineList(_ items: [UIValue], indent: Int) -> String {
        let pad = String(repeating: indentUnit, count: indent)
        let childPad = String(repeating: indentUnit, count: indent + 1)
        if items.isEmpty {
            return "[]"
        }
        var lines: [String] = ["["]
        for (offset, item) in items.enumerated() {
            let separator = offset == items.count - 1 ? "" : ","
            lines.append(childPad + serialize(item, indent: indent + 1) + separator)
        }
        lines.append(pad + "]")
        return lines.joined(separator: "\n")
    }

    private func multilineRecord(name: String?, record: UIRecord, indent: Int) -> String {
        let pad = String(repeating: indentUnit, count: indent)
        let childPad = String(repeating: indentUnit, count: indent + 1)
        let prefix = name ?? ""
        if record.entries.isEmpty {
            return "\(prefix)()"
        }
        var lines: [String] = ["\(prefix)("]
        for (offset, entry) in record.entries.enumerated() {
            let separator = offset == record.entries.count - 1 ? "" : ","
            lines.append(childPad + serializeEntry(entry, indent: indent + 1) + separator)
        }
        lines.append(pad + ")")
        return lines.joined(separator: "\n")
    }

    private func serializeEntry(_ entry: UIRecordEntry, indent: Int) -> String {
        switch entry.kind {
        case .field(let name):
            return "\(name): \(serialize(entry.value, indent: indent))"
        case .spread:
            return "..." + serialize(entry.value, indent: indent)
        }
    }

    public func inlineValue(_ value: UIValue) -> String? {
        switch value {
        case .number(let number, let isInteger):
            return formatNumber(number, isInteger: isInteger)
        case .string(let text):
            return "\"\(escape(text))\""
        case .boolean(let flag):
            return flag ? "true" : "false"
        case .color(let color):
            if let alpha = color.alpha {
                return "#\(color.hex)(\(formatNumber(alpha, isInteger: false)))"
            }
            return "#\(color.hex)"
        case .identifier(let name):
            return name
        case .binding(let path):
            return "%\(path)"
        case .reference(let reference):
            return reference.displayName
        case .unary(let op, let operand):
            guard let inner = inlineValue(operand) else { return nil }
            return op.rawValue + inner
        case .binary(let op, let lhs, let rhs):
            guard let left = inlineValue(lhs), let right = inlineValue(rhs) else { return nil }
            return "\(left) \(op.rawValue) \(right)"
        case .grouping(let inner):
            guard let text = inlineValue(inner) else { return nil }
            return "(\(text))"
        case .record(let record):
            return inlineRecord(name: nil, record: record)
        case .constructor(let name, let record):
            return inlineRecord(name: name, record: record)
        case .list(let items):
            var parts: [String] = []
            for item in items {
                guard let inner = inlineValue(item) else { return nil }
                parts.append(inner)
            }
            return "[" + parts.joined(separator: ", ") + "]"
        case .element:
            return nil
        }
    }

    private func inlineRecord(name: String?, record: UIRecord) -> String? {
        let prefix = name ?? ""
        if record.entries.isEmpty {
            return "\(prefix)()"
        }
        var parts: [String] = []
        for entry in record.entries {
            switch entry.kind {
            case .field(let fieldName):
                guard let inner = inlineValue(entry.value) else { return nil }
                parts.append("\(fieldName): \(inner)")
            case .spread:
                guard let inner = inlineValue(entry.value) else { return nil }
                parts.append("..." + inner)
            }
        }
        return "\(prefix)(" + parts.joined(separator: ", ") + ")"
    }

    private func formatNumber(_ number: Double, isInteger: Bool) -> String {
        if isInteger && number.isFinite && abs(number) < 1e15 {
            return String(Int(number.rounded()))
        }
        return String(number)
    }

    private func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.append(character)
            }
        }
        return result
    }
}

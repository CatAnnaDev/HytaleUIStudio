import Foundation

public struct ResolvedNode: Sendable {
    public var typeName: String
    public var componentName: String?
    public var id: String?
    public var properties: [(name: String, value: UIValue)]
    public var children: [ResolvedNode]
    public var sourceRange: SourceRange

    public init(typeName: String, componentName: String? = nil, id: String? = nil, properties: [(name: String, value: UIValue)] = [], children: [ResolvedNode] = [], sourceRange: SourceRange = .unknown) {
        self.typeName = typeName
        self.componentName = componentName
        self.id = id
        self.properties = properties
        self.children = children
        self.sourceRange = sourceRange
    }

    public func property(_ name: String) -> UIValue? {
        for entry in properties where entry.name == name {
            return entry.value
        }
        return nil
    }
}

public final class ModuleLoader {
    private var cache: [String: UIDocument] = [:]
    private let readFile: (URL) -> String?

    public init(readFile: @escaping (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }) {
        self.readFile = readFile
    }

    public func document(at url: URL) -> UIDocument? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached }
        guard let source = readFile(url) else { return nil }
        let result = Parser.parse(source)
        cache[key] = result.document
        return result.document
    }
}

public final class Scope {
    public let baseURL: URL?
    public let loader: ModuleLoader
    public let assetResolver: AssetResolver
    public var definitions: [String: UIValue]
    public var imports: [String: String]
    public let parent: Scope?
    private var moduleScopes: [String: Scope] = [:]

    public init(document: UIDocument, baseURL: URL?, loader: ModuleLoader, assetResolver: AssetResolver, parent: Scope? = nil) {
        self.baseURL = baseURL
        self.loader = loader
        self.assetResolver = assetResolver
        self.parent = parent
        self.definitions = [:]
        self.imports = [:]
        for statement in document.statements {
            switch statement {
            case .definition(let definition):
                definitions[definition.name] = definition.value
            case .importDeclaration(let declaration):
                imports[declaration.variable] = declaration.path
            case .element:
                break
            }
        }
    }

    public init(definitions: [String: UIValue], parent: Scope) {
        self.baseURL = parent.baseURL
        self.loader = parent.loader
        self.assetResolver = parent.assetResolver
        self.parent = parent
        self.definitions = definitions
        self.imports = [:]
    }

    public func lookupDefinition(_ name: String) -> UIValue? {
        if let value = definitions[name] { return value }
        return parent?.lookupDefinition(name)
    }

    public func lookupImportPath(_ variable: String) -> String? {
        if let path = imports[variable] { return path }
        return parent?.lookupImportPath(variable)
    }

    public func allDefinitionNames() -> Set<String> {
        var names = Set(definitions.keys)
        if let parent { names.formUnion(parent.allDefinitionNames()) }
        return names
    }

    public func moduleScope(for variable: String) -> Scope? {
        if let cached = moduleScopes[variable] { return cached }
        guard let path = lookupImportPath(variable), let baseURL else { return nil }
        guard let url = assetResolver.resolve(importPath: path, from: baseURL), let document = loader.document(at: url) else { return nil }
        let scope = Scope(document: document, baseURL: url, loader: loader, assetResolver: assetResolver)
        moduleScopes[variable] = scope
        return scope
    }
}

public final class Resolver {
    private let loader: ModuleLoader
    private let assetResolver: AssetResolver
    private var expanding: Set<String> = []
    public private(set) var unresolved: [String] = []

    public init(loader: ModuleLoader = ModuleLoader(), assetResolver: AssetResolver = AssetResolver()) {
        self.loader = loader
        self.assetResolver = assetResolver
    }

    public func resolveRoots(document: UIDocument, baseURL: URL?) -> [ResolvedNode] {
        let scope = Scope(document: document, baseURL: baseURL, loader: loader, assetResolver: assetResolver)
        var nodes: [ResolvedNode] = []
        for statement in document.statements {
            if case .element(let element) = statement {
                nodes.append(resolveElement(element, scope: scope))
            }
        }
        return nodes
    }

    public func analyzeRequirements(document: UIDocument, baseURL: URL?) -> [Diagnostic] {
        let scope = Scope(document: document, baseURL: baseURL, loader: loader, assetResolver: assetResolver)
        var diagnostics: [Diagnostic] = []
        for statement in document.statements {
            if case .element(let element) = statement {
                checkRequirements(element, scope: scope, into: &diagnostics)
            }
        }
        return diagnostics
    }

    private func checkRequirements(_ element: UIElement, scope: Scope, into diagnostics: inout [Diagnostic]) {
        switch element.type {
        case .component(let reference):
            if let (template, moduleDefs) = templateInfo(for: reference, scope: scope) {
                let declared = Set(template.parameters.map(\.name))
                var referenced: Set<String> = []
                collectBareMacros(in: template, into: &referenced)
                let required = referenced.subtracting(declared).subtracting(moduleDefs)
                let provided = Set(element.parameters.map(\.name))
                for missing in required.subtracting(provided).sorted() {
                    diagnostics.append(Diagnostic(severity: .warning, message: "Paramètre requis manquant : @\(missing)", range: element.range))
                }
            }
        case .builtin(let name):
            if ["Label", "TextButton", "ActionButton", "ToggleButton"].contains(name), element.property("Text") == nil {
                diagnostics.append(Diagnostic(severity: .warning, message: "\(name) sans propriété Text", range: element.range))
            }
        case .slot:
            break
        }
        for child in element.children {
            checkRequirements(child, scope: scope, into: &diagnostics)
        }
    }

    private func templateInfo(for reference: UIReference, scope: Scope) -> (element: UIElement, moduleDefs: Set<String>)? {
        let moduleScope = moduleScopeForReference(reference, scope: scope)
        let baseValue: UIValue?
        if reference.module != nil {
            baseValue = moduleScope.lookupDefinition(reference.name)
        } else {
            baseValue = scope.lookupDefinition(reference.name)
        }
        guard case .element(let template)? = baseValue else { return nil }
        return (template, moduleScope.allDefinitionNames())
    }

    private func collectBareMacros(in element: UIElement, into result: inout Set<String>) {
        for member in element.members {
            switch member {
            case .property(let property), .parameter(let property):
                collectBareMacros(in: property.value, into: &result)
            case .child(let child):
                collectBareMacros(in: child, into: &result)
            }
        }
    }

    private func collectBareMacros(in value: UIValue, into result: inout Set<String>) {
        switch value {
        case .reference(let reference):
            if reference.module == nil { result.insert(reference.name) }
        case .record(let record):
            for entry in record.entries { collectBareMacros(in: entry.value, into: &result) }
        case .constructor(_, let record):
            for entry in record.entries { collectBareMacros(in: entry.value, into: &result) }
        case .list(let items):
            for item in items { collectBareMacros(in: item, into: &result) }
        case .element(let element):
            collectBareMacros(in: element, into: &result)
        case .unary(_, let operand):
            collectBareMacros(in: operand, into: &result)
        case .binary(_, let lhs, let rhs):
            collectBareMacros(in: lhs, into: &result)
            collectBareMacros(in: rhs, into: &result)
        case .grouping(let inner):
            collectBareMacros(in: inner, into: &result)
        default:
            break
        }
    }

    public func resolveElement(_ element: UIElement, scope: Scope) -> ResolvedNode {
        switch element.type {
        case .builtin(let name):
            return buildNode(typeName: name, componentName: nil, element: element, scope: scope)
        case .slot:
            return buildNode(typeName: "#slot", componentName: nil, element: element, scope: scope)
        case .component(let reference):
            return expandComponent(reference: reference, instance: element, scope: scope)
        }
    }

    private func buildNode(typeName: String, componentName: String?, element: UIElement, scope: Scope) -> ResolvedNode {
        var properties: [(name: String, value: UIValue)] = []
        var children: [ResolvedNode] = []
        for member in element.members {
            switch member {
            case .property(let property):
                properties.append((property.name, resolveValue(property.value, scope: scope)))
            case .parameter:
                break
            case .child(let child):
                children.append(resolveElement(child, scope: scope))
            }
        }
        return ResolvedNode(typeName: typeName, componentName: componentName, id: element.id, properties: properties, children: children, sourceRange: element.range)
    }

    private func expandComponent(reference: UIReference, instance: UIElement, scope: Scope) -> ResolvedNode {
        let key = reference.displayName
        guard let template = resolveReference(reference, scope: scope), case .element(let templateElement) = template, !expanding.contains(key) else {
            unresolved.append(key)
            var node = buildNode(typeName: reference.name.isEmpty ? "Group" : reference.name, componentName: reference.displayName, element: instance, scope: scope)
            node.componentName = reference.displayName
            return node
        }

        expanding.insert(key)
        defer { expanding.remove(key) }

        let templateScope = moduleScopeForReference(reference, scope: scope)

        var parameters: [String: UIValue] = [:]
        for member in templateElement.members {
            if case .parameter(let parameter) = member {
                parameters[parameter.name] = parameter.value
            }
        }
        for member in instance.members {
            if case .parameter(let parameter) = member {
                parameters[parameter.name] = resolveValue(parameter.value, scope: scope)
            }
        }

        let expansionScope = Scope(definitions: parameters, parent: templateScope)
        var node = buildNode(typeName: templateElement.type.displayNameOrGroup, componentName: reference.displayName, element: templateElement, scope: expansionScope)
        if case .component(let innerReference) = templateElement.type {
            node = expandComponent(reference: innerReference, instance: strippedElement(templateElement), scope: expansionScope)
            node.componentName = reference.displayName
        }

        node.id = instance.id ?? node.id

        for member in instance.members {
            switch member {
            case .property(let property):
                overrideProperty(&node, name: property.name, value: resolveValue(property.value, scope: scope))
            case .child(let child):
                let resolvedChild = resolveElement(child, scope: scope)
                if case .slot = child.type, let slotID = child.id {
                    mergeSlot(&node, slotID: slotID, incoming: resolvedChild)
                } else {
                    node.children.append(resolvedChild)
                }
            case .parameter:
                break
            }
        }
        return node
    }

    private func strippedElement(_ element: UIElement) -> UIElement {
        var copy = element
        copy.members = element.members.filter { member in
            if case .parameter = member { return false }
            return true
        }
        return copy
    }

    private func moduleScopeForReference(_ reference: UIReference, scope: Scope) -> Scope {
        if let module = reference.module, let moduleScope = scope.moduleScope(for: module) {
            return moduleScope
        }
        return scope
    }

    private func overrideProperty(_ node: inout ResolvedNode, name: String, value: UIValue) {
        for index in node.properties.indices where node.properties[index].name == name {
            node.properties[index].value = value
            return
        }
        node.properties.append((name, value))
    }

    private func mergeSlot(_ node: inout ResolvedNode, slotID: String, incoming: ResolvedNode) {
        if node.id == slotID {
            node.children.append(contentsOf: incoming.children)
            for property in incoming.properties {
                overrideProperty(&node, name: property.name, value: property.value)
            }
            return
        }
        for index in node.children.indices {
            var child = node.children[index]
            if mergeSlotRecursive(&child, slotID: slotID, incoming: incoming) {
                node.children[index] = child
                return
            }
            node.children[index] = child
        }
        node.children.append(incoming)
    }

    private func mergeSlotRecursive(_ node: inout ResolvedNode, slotID: String, incoming: ResolvedNode) -> Bool {
        if node.id == slotID {
            node.children.append(contentsOf: incoming.children)
            for property in incoming.properties {
                overrideProperty(&node, name: property.name, value: property.value)
            }
            return true
        }
        for index in node.children.indices {
            var child = node.children[index]
            if mergeSlotRecursive(&child, slotID: slotID, incoming: incoming) {
                node.children[index] = child
                return true
            }
        }
        return false
    }

    public func resolveReference(_ reference: UIReference, scope: Scope) -> UIValue? {
        var baseValue: UIValue?
        if let module = reference.module {
            baseValue = scope.moduleScope(for: module)?.lookupDefinition(reference.name)
        } else {
            baseValue = scope.lookupDefinition(reference.name)
        }
        guard var value = baseValue else { return nil }
        let referenceScope = moduleScopeForReference(reference, scope: scope)
        value = resolveValue(value, scope: referenceScope)
        for field in reference.fields {
            value = fieldAccess(value, field: field) ?? value
        }
        return value
    }

    private func fieldAccess(_ value: UIValue, field: String) -> UIValue? {
        switch value {
        case .record(let record):
            return record.value(field)
        case .constructor(_, let record):
            return record.value(field)
        default:
            return nil
        }
    }

    public func resolveValue(_ value: UIValue, scope: Scope) -> UIValue {
        switch value {
        case .reference(let reference):
            if let resolved = resolveReference(reference, scope: scope) {
                return resolved
            }
            return value
        case .record(let record):
            return .record(resolveRecord(record, scope: scope))
        case .constructor(let name, let record):
            return .constructor(name: name, record: resolveRecord(record, scope: scope))
        case .list(let items):
            return .list(items.map { resolveValue($0, scope: scope) })
        case .grouping(let inner):
            if let number = numericValue(value, scope: scope) {
                return .number(number, isInteger: number.rounded() == number)
            }
            return .grouping(resolveValue(inner, scope: scope))
        case .unary, .binary:
            if let number = numericValue(value, scope: scope) {
                return .number(number, isInteger: number.rounded() == number)
            }
            return value
        default:
            return value
        }
    }

    private func resolveRecord(_ record: UIRecord, scope: Scope) -> UIRecord {
        var merged: [(name: String?, value: UIValue)] = []
        func upsert(name: String?, value: UIValue) {
            if let name {
                for index in merged.indices where merged[index].name == name {
                    merged[index].value = value
                    return
                }
            }
            merged.append((name, value))
        }
        for entry in record.entries {
            switch entry.kind {
            case .field(let name):
                upsert(name: name, value: resolveValue(entry.value, scope: scope))
            case .spread:
                let resolved = resolveValue(entry.value, scope: scope)
                if case .record(let spreadRecord) = resolved {
                    for spreadEntry in spreadRecord.entries {
                        if case .field(let spreadName) = spreadEntry.kind {
                            upsert(name: spreadName, value: spreadEntry.value)
                        } else {
                            merged.append((nil, spreadEntry.value))
                        }
                    }
                } else if case .constructor(_, let spreadRecord) = resolved {
                    for spreadEntry in spreadRecord.entries {
                        if case .field(let spreadName) = spreadEntry.kind {
                            upsert(name: spreadName, value: spreadEntry.value)
                        }
                    }
                }
            }
        }
        return UIRecord(entries: merged.map { pair in
            if let name = pair.name {
                return UIRecordEntry(kind: .field(name: name), value: pair.value)
            }
            return UIRecordEntry(kind: .spread, value: pair.value)
        })
    }

    public func numericValue(_ value: UIValue, scope: Scope) -> Double? {
        switch value {
        case .number(let number, _):
            return number
        case .grouping(let inner):
            return numericValue(inner, scope: scope)
        case .unary(let op, let operand):
            guard let inner = numericValue(operand, scope: scope) else { return nil }
            return op == .negate ? -inner : inner
        case .binary(let op, let lhs, let rhs):
            guard let left = numericValue(lhs, scope: scope), let right = numericValue(rhs, scope: scope) else { return nil }
            switch op {
            case .add: return left + right
            case .subtract: return left - right
            case .multiply: return left * right
            case .divide: return right == 0 ? nil : left / right
            }
        case .reference(let reference):
            guard let resolved = resolveReference(reference, scope: scope) else { return nil }
            return numericValue(resolved, scope: scope)
        default:
            return nil
        }
    }
}

private extension UIElementType {
    var displayNameOrGroup: String {
        switch self {
        case .builtin(let name): return name
        case .slot: return "#slot"
        case .component: return "Group"
        }
    }
}

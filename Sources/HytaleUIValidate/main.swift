import Foundation
import AppKit
import HytaleUICore
import HytaleUIRender

func detectGameData() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = home.appendingPathComponent("Library/Application Support/Hytale/install/release/package/game/latest/Client/Hytale.app/Contents/Resources/Data")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: uivalidate <directory-or-listfile> [maxErrors]")
    exit(2)
}

if arguments[1] == "--diff", arguments.count >= 3 {
    let file = arguments[2]
    let source = try! String(contentsOfFile: file, encoding: .utf8)
    let first = Parser.parse(source)
    for diagnostic in first.diagnostics where diagnostic.severity == .error {
        print("DIAG \(diagnostic)")
    }
    let serializer = Serializer()
    let text = serializer.serialize(first.document)
    let second = Parser.parse(text)
    print("EQUAL: \(second.document == first.document)")
    try! String(reflecting: first.document).write(toFile: "/tmp/ast_a.txt", atomically: true, encoding: .utf8)
    try! String(reflecting: second.document).write(toFile: "/tmp/ast_b.txt", atomically: true, encoding: .utf8)
    try! text.write(toFile: "/tmp/serialized.ui", atomically: true, encoding: .utf8)
    print("wrote /tmp/ast_a.txt /tmp/ast_b.txt /tmp/serialized.ui")
    exit(0)
}

if arguments[1] == "--catalog", arguments.count >= 4 {
    let target = arguments[2]
    let outputPath = arguments[3]
    let files = collectFiles(target)

    var widgets = Set<String>()
    var widgetProperties: [String: Set<String>] = [:]
    var enumValues: [String: Set<String>] = [:]
    var recordFields: [String: Set<String>] = [:]
    var constructors = Set<String>()
    var propertyConstructors: [String: Set<String>] = [:]
    var propertyKinds: [String: Set<String>] = [:]

    func note(_ dictionary: inout [String: Set<String>], _ key: String, _ value: String) {
        dictionary[key, default: []].insert(value)
    }

    func walkValue(owner: String, _ value: UIValue) {
        switch value {
        case .identifier(let name):
            note(&enumValues, owner, name); note(&propertyKinds, owner, "enum")
        case .number:
            note(&propertyKinds, owner, "number")
        case .string:
            note(&propertyKinds, owner, "string")
        case .boolean:
            note(&propertyKinds, owner, "bool")
        case .color:
            note(&propertyKinds, owner, "color")
        case .binding:
            note(&propertyKinds, owner, "binding")
        case .reference:
            note(&propertyKinds, owner, "reference")
        case .record(let record):
            note(&propertyKinds, owner, "record")
            for entry in record.entries {
                if case .field(let field) = entry.kind {
                    note(&recordFields, owner, field)
                    walkValue(owner: field, entry.value)
                } else {
                    walkValue(owner: owner, entry.value)
                }
            }
        case .constructor(let name, let record):
            constructors.insert(name)
            note(&propertyConstructors, owner, name)
            note(&propertyKinds, owner, "constructor")
            for entry in record.entries {
                if case .field(let field) = entry.kind {
                    note(&recordFields, name, field)
                    walkValue(owner: field, entry.value)
                } else {
                    walkValue(owner: name, entry.value)
                }
            }
        case .list(let items):
            note(&propertyKinds, owner, "list")
            for item in items { walkValue(owner: owner, item) }
        case .element(let element):
            walkElement(element, isDefinition: false)
        case .unary(_, let operand):
            note(&propertyKinds, owner, "expr"); walkValue(owner: owner, operand)
        case .binary(_, let lhs, let rhs):
            note(&propertyKinds, owner, "expr"); walkValue(owner: owner, lhs); walkValue(owner: owner, rhs)
        case .grouping(let inner):
            walkValue(owner: owner, inner)
        }
    }

    func walkElement(_ element: UIElement, isDefinition: Bool) {
        var widgetName: String? = nil
        if case .builtin(let name) = element.type {
            widgets.insert(name)
            widgetName = name
        }
        for member in element.members {
            switch member {
            case .property(let property), .parameter(let property):
                if let widgetName { note(&widgetProperties, widgetName, property.name) }
                walkValue(owner: property.name, property.value)
            case .child(let child):
                walkElement(child, isDefinition: false)
            }
        }
    }

    for file in files {
        guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
        let result = Parser.parse(source)
        if result.hasErrors { continue }
        for statement in result.document.statements {
            switch statement {
            case .element(let element):
                walkElement(element, isDefinition: false)
            case .definition(let definition):
                walkValue(owner: definition.name, definition.value)
            case .importDeclaration:
                break
            }
        }
    }

    func dominantKind(_ kinds: Set<String>, property: String) -> String {
        if kinds.contains("enum"), !(enumValues[property]?.isEmpty ?? true) { return "enum" }
        for candidate in ["color", "bool", "number", "string", "binding", "reference", "constructor", "record", "list", "expr"] where kinds.contains(candidate) {
            return candidate
        }
        return "unknown"
    }

    func emitStringArray(_ values: Set<String>) -> String {
        "[" + values.sorted().map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }
    func emitDict(_ dictionary: [String: Set<String>]) -> String {
        var lines: [String] = []
        for key in dictionary.keys.sorted() {
            lines.append("        \"\(key)\": \(emitStringArray(dictionary[key]!)),")
        }
        return lines.joined(separator: "\n")
    }

    var kindDict: [String: String] = [:]
    for (property, kinds) in propertyKinds { kindDict[property] = dominantKind(kinds, property: property) }
    let kindLines = kindDict.keys.sorted().map { "        \"\($0)\": \"\(kindDict[$0]!)\"," }.joined(separator: "\n")

    let swift = """
    import Foundation

    public enum CorpusCatalog {
        public static let widgets: [String] = \(emitStringArray(widgets))

        public static let widgetProperties: [String: [String]] = [
    \(emitDict(widgetProperties))
        ]

        public static let enumValues: [String: [String]] = [
    \(emitDict(enumValues))
        ]

        public static let recordFields: [String: [String]] = [
    \(emitDict(recordFields))
        ]

        public static let constructors: [String] = \(emitStringArray(constructors))

        public static let propertyConstructors: [String: [String]] = [
    \(emitDict(propertyConstructors))
        ]

        public static let propertyKind: [String: String] = [
    \(kindLines)
        ]
    }
    """
    try! swift.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
    print("catalog: \(widgets.count) widgets, \(widgetProperties.count) widget-prop maps, \(enumValues.count) enum keys, \(recordFields.count) record owners, \(constructors.count) constructors -> \(outputPath)")
    exit(0)
}

if arguments[1] == "--dump-catalog-json", arguments.count >= 3 {
    let outputPath = arguments[2]

    func kindTag(_ kind: PropertyKind) -> String {
        switch kind {
        case .color: return "color"
        case .number: return "number"
        case .string: return "string"
        case .boolean: return "boolean"
        case .enumeration(let name): return "enumeration:\(name)"
        case .anchor: return "anchor"
        case .padding: return "padding"
        case .style(let name): return "style:\(name)"
        case .reference: return "reference"
        case .binding: return "binding"
        case .texturePath: return "texturePath"
        case .record: return "record"
        case .list: return "list"
        case .unknown: return "unknown"
        }
    }

    let widgetNames = SemanticCatalog.allWidgetNames()
    var widgetDefs: [String: Any] = [:]
    for name in widgetNames {
        let def = SemanticCatalog.definition(for: name)
        widgetDefs[name] = [
            "category": def.category,
            "isContainer": def.isContainer,
            "summary": def.summary,
            "defaultSize": ["w": def.defaultSize.width, "h": def.defaultSize.height]
        ]
    }

    var enumNames = Set(SemanticCatalog.enumValues.keys)
    enumNames.formUnion(CorpusCatalog.enumValues.keys)
    var enumValuesOut: [String: [String]] = [:]
    for name in enumNames { enumValuesOut[name] = SemanticCatalog.enumOptions(name) }

    var propertyNames = Set(SemanticCatalog.propertyKinds.keys)
    propertyNames.formUnion(CorpusCatalog.propertyKind.keys)
    propertyNames.formUnion(CorpusCatalog.enumValues.keys)
    for props in CorpusCatalog.widgetProperties.values { propertyNames.formUnion(props) }
    for fields in CorpusCatalog.recordFields.values { propertyNames.formUnion(fields) }
    var propertyKindsOut: [String: String] = [:]
    for name in propertyNames { propertyKindsOut[name] = kindTag(SemanticCatalog.kind(for: name)) }

    let payload: [String: Any] = [
        "widgets": widgetNames,
        "widgetDefs": widgetDefs,
        "enumValues": enumValuesOut,
        "propertyKinds": propertyKindsOut,
        "widgetProperties": CorpusCatalog.widgetProperties,
        "recordFields": CorpusCatalog.recordFields,
        "constructors": CorpusCatalog.constructors,
        "propertyConstructors": CorpusCatalog.propertyConstructors,
        "minedPropertyKind": CorpusCatalog.propertyKind
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: outputPath))
    print("catalog json: \(widgetNames.count) widgets, \(enumValuesOut.count) enums, \(propertyKindsOut.count) property kinds -> \(outputPath)")
    exit(0)
}

if arguments[1] == "--render", arguments.count >= 4 {
    let file = arguments[2]
    let outputPath = arguments[3]
    let scale = arguments.count >= 5 ? (Double(arguments[4]) ?? 0.6) : 0.6
    let url = URL(fileURLWithPath: file)
    let source = try! String(contentsOf: url, encoding: .utf8)
    let document = Parser.parse(source).document
    let assetRoots = AssetRootFinder.discover(near: url)
    let resolver = Resolver(assetResolver: AssetResolver(assetRoots: assetRoots))
    let roots = resolver.resolveRoots(document: document, baseURL: url)
    guard !roots.isEmpty else {
        print("no root element")
        exit(1)
    }
    var size = UISize(width: 1920, height: 1080)
    if roots.count == 1, case .record(let record)? = roots[0].property("Anchor"),
       let width = RenderReader.number(record.value("Width")),
       let height = RenderReader.number(record.value("Height")) {
        size = UISize(width: width, height: height)
    }
    var textureRoots = TextureStore.textureRoots(documentURL: url, gameDataURL: detectGameData())
    textureRoots.append(contentsOf: assetRoots.map { $0.appendingPathComponent("Common/UI") })
    let textures = TextureStore(roots: textureRoots)
    let renderer = SceneRenderer(textures: textures)
    let backdrop = NSColor(white: 0.12, alpha: 1)
    let image = renderer.render(roots: roots, size: size, scale: CGFloat(scale), backdrop: backdrop)
    if let data = image.pngData() {
        try! data.write(to: URL(fileURLWithPath: outputPath))
        print("rendered \(Int(size.width))x\(Int(size.height)) at scale \(scale) -> \(outputPath)")
        print("unresolved: \(Set(resolver.unresolved).sorted().prefix(12).joined(separator: ", "))")
    }
    exit(0)
}

if arguments[1] == "--layout", arguments.count >= 3 {
    let file = arguments[2]
    let url = URL(fileURLWithPath: file)
    let source = try! String(contentsOf: url, encoding: .utf8)
    let result = Parser.parse(source)
    let resolver = Resolver()
    let roots = resolver.resolveRoots(document: result.document, baseURL: url)
    let engine = LayoutEngine()
    let viewport = UIRect(x: 0, y: 0, width: 1920, height: 1080)
    func dump(_ node: LaidOutNode, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        let frame = node.frame
        let name = node.componentName.map { "\(node.typeName)<\($0)>" } ?? node.typeName
        let identifier = node.id.map { " #\($0)" } ?? ""
        print("\(pad)\(name)\(identifier)  [x:\(Int(frame.x)) y:\(Int(frame.y)) w:\(Int(frame.width)) h:\(Int(frame.height))]")
        for child in node.children {
            dump(child, depth: depth + 1)
        }
    }
    for root in roots {
        dump(engine.layout(root: root, in: viewport), depth: 0)
    }
    print("unresolved refs: \(Set(resolver.unresolved).sorted().prefix(20).joined(separator: ", "))")
    exit(0)
}

let target = arguments[1]
let maxErrors = arguments.count >= 3 ? Int(arguments[2]) ?? 20 : 20

func collectFiles(_ path: String) -> [String] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
    if isDirectory.boolValue {
        var results: [String] = []
        if let enumerator = fileManager.enumerator(atPath: path) {
            for case let name as String in enumerator where name.hasSuffix(".ui") {
                results.append((path as NSString).appendingPathComponent(name))
            }
        }
        return results.sorted()
    }
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return content.split(separator: "\n").map(String.init).filter { $0.hasSuffix(".ui") }
}

let files = collectFiles(target)
guard !files.isEmpty else {
    print("no .ui files found at \(target)")
    exit(1)
}

var parseErrorFiles = 0
var roundTripFailures = 0
var totalDiagnostics = 0
var reportedErrors = 0
var reportedRoundTrips = 0

for file in files {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
    let result = Parser.parse(source)
    let errors = result.diagnostics.filter { $0.severity == .error }
    totalDiagnostics += errors.count
    if !errors.isEmpty {
        parseErrorFiles += 1
        if reportedErrors < maxErrors {
            reportedErrors += 1
            print("PARSE ERROR \(file)")
            for diagnostic in errors.prefix(3) {
                print("    \(diagnostic)")
            }
        }
        continue
    }
    let serializer = Serializer()
    let text = serializer.serialize(result.document)
    let reparsed = Parser.parse(text)
    if reparsed.document != result.document {
        roundTripFailures += 1
        if reportedRoundTrips < maxErrors {
            reportedRoundTrips += 1
            print("ROUNDTRIP MISMATCH \(file)")
        }
    }
}

print("")
print("files:              \(files.count)")
print("parse-error files:  \(parseErrorFiles)")
print("roundtrip failures: \(roundTripFailures)")
print("total error diags:  \(totalDiagnostics)")
if parseErrorFiles == 0 && roundTripFailures == 0 {
    print("ALL FILES PARSE AND ROUND-TRIP CLEANLY")
}

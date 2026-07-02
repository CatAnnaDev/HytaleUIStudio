import Foundation
import SwiftUI
import HytaleUICore
import HytaleUIRender

@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: UIDocument
    @Published var sourceText: String
    @Published var diagnostics: [Diagnostic] = []
    @Published var selectedPath: [Int]? = nil
    @Published var fileURL: URL? = nil
    @Published var demoBaseURL: URL? = nil
    @Published var gameDataURL: URL?
    @Published var canvasSize: UISize = UISize(width: 960, height: 600)

    @Published var requirementWarnings: [Diagnostic] = []
    @Published var scrollTarget: Int? = nil

    let textures = TextureStore()
    let moduleLoader = ModuleLoader()
    private var undoStack: [UIDocument] = []
    private var redoStack: [UIDocument] = []
    private var suppressSourceSync = false
    private(set) var assetRoots: [URL] = []

    private func makeResolver() -> Resolver {
        Resolver(loader: moduleLoader, assetResolver: AssetResolver(assetRoots: assetRoots))
    }

    func recomputeWarnings() {
        requirementWarnings = makeResolver().analyzeRequirements(document: document, baseURL: effectiveBaseURL)
    }

    func moduleMemberNames(_ variable: String) -> [String] {
        guard let base = effectiveBaseURL else { return [] }
        let path = document.statements.compactMap { statement -> String? in
            if case .importDeclaration(let declaration) = statement, declaration.variable == variable { return declaration.path }
            return nil
        }.first
        guard let path, let url = AssetResolver(assetRoots: assetRoots).resolve(importPath: path, from: base), let doc = moduleLoader.document(at: url) else { return [] }
        return doc.statements.compactMap { if case .definition(let definition) = $0 { return definition.name } else { return nil } }
    }

    var effectiveBaseURL: URL? { fileURL ?? demoBaseURL }

    init() {
        let starter = DocumentStore.starterDocument()
        self.document = starter
        self.sourceText = Serializer().serialize(starter)
        self.gameDataURL = AppEnvironment.detectGameDataURL()
        refreshTextureRoots()
        loadDemoIfAvailable()
    }

    func loadDemoIfAvailable() {
        guard let gameDataURL else { return }
        let demo = gameDataURL.appendingPathComponent("Game/Interface/FeedbackDialog.ui")
        guard let text = try? String(contentsOf: demo, encoding: .utf8) else { return }
        demoBaseURL = demo
        applySource(text, updatingDocument: true)
        selectedPath = rootElementPaths().first
        recomputeAssetRoots()
        refreshTextureRoots()
        recomputeWarnings()
    }

    static func starterDocument() -> UIDocument {
        let anchor = UIValue.record(UIRecord(entries: [
            UIRecordEntry(kind: .field(name: "Width"), value: .number(400, isInteger: true)),
            UIRecordEntry(kind: .field(name: "Height"), value: .number(300, isInteger: true))
        ]))
        let root = UIElement(type: .builtin("Group"), id: "Root", members: [
            .property(UIProperty(name: "LayoutMode", value: .identifier("Top"))),
            .property(UIProperty(name: "Anchor", value: anchor)),
            .property(UIProperty(name: "Background", value: .record(UIRecord(entries: [
                UIRecordEntry(kind: .field(name: "Color"), value: .color(UIColor(hex: "1b2a3a", alpha: 0.85)))
            ]))))
        ])
        return UIDocument(statements: [.element(root)])
    }

    func recomputeAssetRoots() {
        assetRoots = AssetRootFinder.discover(near: effectiveBaseURL)
    }

    func refreshTextureRoots() {
        var roots = TextureStore.textureRoots(documentURL: effectiveBaseURL, gameDataURL: gameDataURL)
        roots.append(contentsOf: assetRoots.map { $0.appendingPathComponent("Common/UI") })
        textures.setRoots(roots)
    }

    func loadFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        fileURL = url
        demoBaseURL = nil
        applySource(text, updatingDocument: true)
        selectedPath = rootElementPaths().first
        undoStack.removeAll()
        redoStack.removeAll()
        recomputeAssetRoots()
        refreshTextureRoots()
        recomputeWarnings()
    }

    func newDocument() {
        let starter = DocumentStore.starterDocument()
        document = starter
        fileURL = nil
        demoBaseURL = nil
        selectedPath = rootElementPaths().first
        undoStack.removeAll()
        redoStack.removeAll()
        regenerateSource()
        recomputeAssetRoots()
        refreshTextureRoots()
    }

    func applySource(_ text: String, updatingDocument: Bool) {
        sourceText = text
        let result = Parser.parse(text)
        diagnostics = result.diagnostics
        if updatingDocument && !result.hasErrors {
            document = result.document
        }
    }

    func onSourceEdited() {
        if suppressSourceSync { return }
        let result = Parser.parse(sourceText)
        diagnostics = result.diagnostics
        if !result.hasErrors {
            document = result.document
            if let path = selectedPath, element(at: path) == nil {
                selectedPath = rootElementPaths().first
            }
            recomputeWarnings()
        }
    }

    func regenerateSource() {
        suppressSourceSync = true
        sourceText = Serializer().serialize(document)
        let result = Parser.parse(sourceText)
        diagnostics = result.diagnostics
        suppressSourceSync = false
        recomputeWarnings()
    }

    func save() {
        guard let fileURL else { return }
        try? sourceText.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func saveAs(_ url: URL) {
        fileURL = url
        try? sourceText.write(to: url, atomically: true, encoding: .utf8)
        refreshTextureRoots()
    }

    func rootElements() -> [UIElement] {
        document.statements.compactMap { if case .element(let element) = $0 { return element } else { return nil } }
    }

    func rootElementPaths() -> [[Int]] {
        rootElements().indices.map { [$0] }
    }

    func element(at path: [Int]) -> UIElement? {
        guard let first = path.first else { return nil }
        let roots = rootElements()
        guard first < roots.count else { return nil }
        return descend(roots[first], path: Array(path.dropFirst()))
    }

    private func descend(_ element: UIElement, path: [Int]) -> UIElement? {
        guard let index = path.first else { return element }
        let children = element.children
        guard index < children.count else { return nil }
        return descend(children[index], path: Array(path.dropFirst()))
    }

    func pushUndo() {
        undoStack.append(document)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        regenerateSource()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        regenerateSource()
    }

    func updateElement(at path: [Int], _ transform: (inout UIElement) -> Void) {
        guard let first = path.first else { return }
        var statements = document.statements
        var elementOrdinal = 0
        for index in statements.indices {
            guard case .element(var element) = statements[index] else { continue }
            if elementOrdinal == first {
                pushUndo()
                element = updateDescendant(element, path: Array(path.dropFirst()), transform: transform)
                statements[index] = .element(element)
                document = UIDocument(statements: statements)
                regenerateSource()
                return
            }
            elementOrdinal += 1
        }
    }

    private func updateDescendant(_ element: UIElement, path: [Int], transform: (inout UIElement) -> Void) -> UIElement {
        var copy = element
        if path.isEmpty {
            transform(&copy)
            return copy
        }
        guard let childOrdinal = path.first else { return copy }
        var childCounter = 0
        for memberIndex in copy.members.indices {
            if case .child(let child) = copy.members[memberIndex] {
                if childCounter == childOrdinal {
                    let updated = updateDescendant(child, path: Array(path.dropFirst()), transform: transform)
                    copy.members[memberIndex] = .child(updated)
                    return copy
                }
                childCounter += 1
            }
        }
        return copy
    }

    func setProperty(at path: [Int], name: String, value: UIValue) {
        updateElement(at: path) { element in
            for index in element.members.indices {
                if case .property(var property) = element.members[index], property.name == name {
                    property.value = value
                    element.members[index] = .property(property)
                    return
                }
            }
            element.members.append(.property(UIProperty(name: name, value: value)))
        }
    }

    func removeProperty(at path: [Int], name: String) {
        updateElement(at: path) { element in
            element.members.removeAll { member in
                if case .property(let property) = member, property.name == name { return true }
                return false
            }
        }
    }

    func addChild(at path: [Int], child: UIElement) {
        updateElement(at: path) { element in
            element.members.append(.child(child))
        }
    }

    func removeElement(at path: [Int]) {
        guard path.count >= 1 else { return }
        if path.count == 1 {
            pushUndo()
            var statements = document.statements
            var ordinal = 0
            for index in statements.indices {
                if case .element = statements[index] {
                    if ordinal == path[0] {
                        statements.remove(at: index)
                        document = UIDocument(statements: statements)
                        regenerateSource()
                        selectedPath = rootElementPaths().first
                        return
                    }
                    ordinal += 1
                }
            }
            return
        }
        let parentPath = Array(path.dropLast())
        let childOrdinal = path.last!
        updateElement(at: parentPath) { element in
            var counter = 0
            for memberIndex in element.members.indices {
                if case .child = element.members[memberIndex] {
                    if counter == childOrdinal {
                        element.members.remove(at: memberIndex)
                        return
                    }
                    counter += 1
                }
            }
        }
        selectedPath = parentPath
    }

    func resolvedRoots() -> [ResolvedNode] {
        makeResolver().resolveRoots(document: document, baseURL: effectiveBaseURL)
    }

    func selectedRoot() -> ResolvedNode? {
        let roots = resolvedRoots()
        if let selected = selectedPath?.first, selected < roots.count {
            return roots[selected]
        }
        return roots.first
    }

    func offsetIndex() -> [(range: SourceRange, path: [Int])] {
        var result: [(SourceRange, [Int])] = []
        let roots = rootElements()
        for (index, root) in roots.enumerated() {
            collectRanges(root, path: [index], into: &result)
        }
        return result
    }

    private func collectRanges(_ element: UIElement, path: [Int], into result: inout [(SourceRange, [Int])]) {
        result.append((element.range, path))
        for (childIndex, child) in element.children.enumerated() {
            collectRanges(child, path: path + [childIndex], into: &result)
        }
    }

    func path(forOffset offset: Int) -> [Int]? {
        var best: (range: SourceRange, path: [Int])?
        for entry in offsetIndex() where entry.range.start.offset <= offset && offset < entry.range.end.offset {
            if best == nil || entry.range.start.offset > best!.range.start.offset {
                best = entry
            }
        }
        return best?.path
    }
}

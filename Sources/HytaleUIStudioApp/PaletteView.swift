import SwiftUI
import HytaleUICore

struct PaletteView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Widgets (\(SemanticCatalog.allWidgetNames().count))").font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SemanticCatalog.categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(widgets(in: category), id: \.name) { widget in
                                Button {
                                    addWidget(widget)
                                } label: {
                                    HStack {
                                        Image(systemName: icon(for: category))
                                            .frame(width: 16)
                                        Text(widget.name).font(.system(size: 12))
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(widget.summary)
                                .draggable(widget.name)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    private func widgets(in category: String) -> [WidgetDefinition] {
        SemanticCatalog.allWidgetNames().map { SemanticCatalog.definition(for: $0) }.filter { $0.category == category }
    }

    private func addWidget(_ widget: WidgetDefinition) {
        let element = UIElement(type: .builtin(widget.name), id: nil, members: widget.defaultMembers)
        if let path = targetContainerPath() {
            store.addChild(at: path, child: element)
            store.selectedPath = path + [store.element(at: path)!.children.count - 1]
        } else {
            var statements = store.document.statements
            statements.append(.element(element))
            store.pushUndo()
            store.document = UIDocument(statements: statements)
            store.regenerateSource()
        }
    }

    private func targetContainerPath() -> [Int]? {
        guard let path = store.selectedPath, let element = store.element(at: path) else {
            return store.rootElementPaths().first
        }
        if case .builtin(let name) = element.type, SemanticCatalog.isContainer(name) {
            return path
        }
        if path.count > 1 {
            return Array(path.dropLast())
        }
        return path
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Layout": return "square.on.square"
        case "Text": return "textformat"
        case "Controls": return "button.programmable"
        case "Input": return "character.cursor.ibeam"
        case "Display": return "photo"
        case "Inventory": return "square.grid.3x3"
        case "Preview": return "person.crop.square"
        case "Navigation": return "menubar.rectangle"
        case "Other": return "square.dashed"
        default: return "square"
        }
    }
}

struct SourceView: View {
    @ObservedObject var store: DocumentStore

    private var errors: [Diagnostic] { store.diagnostics.filter { $0.severity == .error } }
    private var warnings: [Diagnostic] { store.requirementWarnings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Source (.ui)").font(.headline)
                Spacer()
                if !errors.isEmpty {
                    Label("\(errors.count)", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                        .help("Syntax errors")
                }
                if !warnings.isEmpty {
                    Label("\(warnings.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .help("Required fields missing")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            CodeEditorView(store: store)

            if !errors.isEmpty || !warnings.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(errors.enumerated()), id: \.offset) { _, diagnostic in
                            issueRow(diagnostic, icon: "exclamationmark.octagon.fill", color: .red)
                        }
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, diagnostic in
                            issueRow(diagnostic, icon: "exclamationmark.triangle.fill", color: .orange)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 108)
                .background(Color(white: 0.1))
            }
        }
    }

    private func issueRow(_ diagnostic: Diagnostic, icon: String, color: Color) -> some View {
        Button {
            store.scrollTarget = diagnostic.range.start.offset
            if let path = store.path(forOffset: diagnostic.range.start.offset) {
                store.selectedPath = path
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color).font(.system(size: 10))
                Text("L\(diagnostic.range.start.line)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text(diagnostic.message).font(.system(size: 11)).foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import AppKit
import HytaleUICore

enum InspectorDefaults {
    static func defaultValue(for property: String) -> UIValue {
        switch SemanticCatalog.kind(for: property) {
        case .color: return .color(UIColor(hex: "ffffff"))
        case .number: return .number(0, isInteger: true)
        case .boolean: return .boolean(true)
        case .string, .texturePath, .binding: return .string("")
        case .enumeration(let name): return .identifier(SemanticCatalog.enumOptions(name).first ?? "None")
        case .anchor, .padding, .record: return .record(UIRecord())
        case .style(let name): return .constructor(name: name, record: UIRecord())
        default: return .string("")
        }
    }

    static func kindLabel(_ property: String) -> String {
        switch SemanticCatalog.kind(for: property) {
        case .color: return "color"
        case .number: return "number"
        case .boolean: return "bool"
        case .string: return "text"
        case .enumeration(let name): return "enum \(name)"
        case .anchor: return "anchor"
        case .padding: return "padding"
        case .reference: return "ref"
        case .binding: return "binding"
        case .texturePath: return "texture"
        case .style(let name): return name
        case .record: return "record"
        case .list: return "list"
        case .unknown: return "value"
        }
    }

    static func uiColor(from color: Color) -> UIColor {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = nsColor.alphaComponent
        return UIColor(hex: String(format: "%02x%02x%02x", r, g, b), alpha: a < 0.999 ? Double((a * 100).rounded()) / 100 : nil)
    }

    static func numberString(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }
}

struct InspectorView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        Group {
            if let path = store.selectedPath, let element = store.element(at: path) {
                inspector(for: element, path: path)
            } else {
                VStack {
                    Spacer()
                    Text("Select an element").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 280)
    }

    @ViewBuilder
    private func inspector(for element: UIElement, path: [Int]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(element, path: path)
                Divider()
                ForEach(Array(element.properties.enumerated()), id: \.offset) { _, property in
                    PropertyRow(store: store, path: path, property: property)
                    Divider().opacity(0.4)
                }
                addPropertyMenu(for: element, path: path)
            }
            .padding(12)
        }
    }

    private func header(_ element: UIElement, path: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(element.type.displayName.isEmpty ? "Slot" : element.type.displayName)
                .font(.headline)
            HStack {
                Text("id").foregroundStyle(.secondary).font(.caption)
                TextField("none", text: Binding(
                    get: { element.id ?? "" },
                    set: { newValue in store.updateElement(at: path) { $0.id = newValue.isEmpty ? nil : newValue } }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func addPropertyMenu(for element: UIElement, path: [Int]) -> some View {
        let existing = Set(element.properties.map(\.name))
        let widgetName: String
        if case .builtin(let name) = element.type { widgetName = name } else { widgetName = "" }
        let suggestions = SemanticCatalog.propertyNames(for: widgetName).filter { !existing.contains($0) }
        return Menu {
            ForEach(suggestions, id: \.self) { name in
                Button("\(name)  ·  \(InspectorDefaults.kindLabel(name))") {
                    store.setProperty(at: path, name: name, value: InspectorDefaults.defaultValue(for: name))
                }
            }
        } label: {
            Label("Add property (\(suggestions.count))", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
    }
}

struct PropertyRow: View {
    @ObservedObject var store: DocumentStore
    let path: [Int]
    let property: UIProperty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(property.name).font(.system(size: 12, weight: .medium))
                Text(InspectorDefaults.kindLabel(property.name)).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button { store.removeProperty(at: path, name: property.name) } label: {
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch SemanticCatalog.kind(for: property.name) {
        case .anchor, .padding:
            AnchorEditor(value: property.value, fields: property.name == "Padding" ? paddingFields : anchorFields) { store.setProperty(at: path, name: property.name, value: $0) }
        default:
            ValueEditorView(value: property.value, ownerName: property.name) { store.setProperty(at: path, name: property.name, value: $0) }
        }
    }

    private var anchorFields: [String] { ["Left", "Top", "Right", "Bottom", "Width", "Height", "Horizontal", "Vertical", "Full"] }
    private var paddingFields: [String] { ["Left", "Top", "Right", "Bottom", "Horizontal", "Vertical", "Full"] }
}

struct ValueEditorView: View {
    let value: UIValue
    let ownerName: String
    let onChange: (UIValue) -> Void

    var body: some View {
        switch value {
        case .record(let record):
            RecordFieldsView(record: record, ownerName: ownerName) { onChange(.record($0)) }
        case .constructor(let name, let record):
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 10, design: .monospaced)).foregroundStyle(.teal)
                RecordFieldsView(record: record, ownerName: name) { onChange(.constructor(name: name, record: $0)) }
            }
        case .list(let items):
            ListEditorView(items: items, ownerName: ownerName, onChange: onChange)
        default:
            scalarEditor
        }
    }

    @ViewBuilder
    private var scalarEditor: some View {
        switch resolvedKind {
        case .color:
            ColorField(value: value, onChange: onChange)
        case .boolean:
            Toggle("", isOn: Binding(get: { if case .boolean(let b) = value { return b } else { return false } }, set: { onChange(.boolean($0)) })).labelsHidden()
        case .number:
            CommitTextField(placeholder: "0", value: displayString) { text in
                if let number = Double(text) { onChange(.number(number, isInteger: number.rounded() == number)) }
            }
        case .enumeration(let name):
            enumEditor(name)
        default:
            CommitTextField(placeholder: "value", value: displayString) { text in
                if let parsed = Parser.parseValue(text) { onChange(parsed.value) }
            }
        }
    }

    private var resolvedKind: PropertyKind {
        let declared = SemanticCatalog.kind(for: ownerName)
        if case .unknown = declared {
            switch value {
            case .color: return .color
            case .boolean: return .boolean
            case .number: return .number
            case .string: return .string
            default: return .unknown
            }
        }
        return declared
    }

    private func enumEditor(_ name: String) -> some View {
        let options = SemanticCatalog.enumOptions(name)
        return Group {
            if options.isEmpty {
                CommitTextField(placeholder: "value", value: displayString) { text in onChange(.identifier(text)) }
            } else {
                Picker("", selection: Binding(
                    get: { if case .identifier(let v) = value { return v } else { return options.first ?? "" } },
                    set: { onChange(.identifier($0)) }
                )) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
            }
        }
    }

    private var displayString: String {
        Serializer().inlineValue(value) ?? Serializer().serialize(value, indent: 0)
    }
}

struct ColorField: View {
    let value: UIValue
    let onChange: (UIValue) -> Void

    var body: some View {
        HStack {
            ColorPicker("", selection: Binding(
                get: { if case .color(let color) = value { return color.swiftUIColor } else { return .white } },
                set: { onChange(.color(InspectorDefaults.uiColor(from: $0))) }
            ), supportsOpacity: true)
            .labelsHidden()
            Text(Serializer().inlineValue(value) ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct RecordFieldsView: View {
    let record: UIRecord
    let ownerName: String
    let onChange: (UIRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(record.entries.enumerated()), id: \.offset) { index, entry in
                entryRow(index: index, entry: entry)
            }
            addFieldMenu
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1) }
    }

    @ViewBuilder
    private func entryRow(index: Int, entry: UIRecordEntry) -> some View {
        switch entry.kind {
        case .field(let name):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).font(.system(size: 11)).foregroundStyle(.blue)
                    Spacer()
                    Button { remove(at: index) } label: { Image(systemName: "minus.circle").font(.system(size: 9)).foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                }
                ValueEditorView(value: entry.value, ownerName: name) { replace(at: index, value: $0) }
            }
        case .spread:
            HStack {
                Text("..." + (Serializer().inlineValue(entry.value) ?? "")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button { remove(at: index) } label: { Image(systemName: "minus.circle").font(.system(size: 9)).foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var addFieldMenu: some View {
        let existing = Set(record.entries.compactMap { entry -> String? in
            if case .field(let name) = entry.kind { return name } else { return nil }
        })
        let suggestions = (CorpusCatalog.recordFields[ownerName] ?? []).filter { !existing.contains($0) }
        return Menu {
            if suggestions.isEmpty {
                Text("No known fields")
            } else {
                ForEach(suggestions, id: \.self) { field in
                    Button("\(field)  ·  \(InspectorDefaults.kindLabel(field))") {
                        var entries = record.entries
                        entries.append(UIRecordEntry(kind: .field(name: field), value: InspectorDefaults.defaultValue(for: field)))
                        onChange(UIRecord(entries: entries))
                    }
                }
            }
        } label: {
            Label("Add field", systemImage: "plus.circle").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton)
    }

    private func replace(at index: Int, value: UIValue) {
        var entries = record.entries
        guard index < entries.count, case .field(let name) = entries[index].kind else { return }
        entries[index] = UIRecordEntry(kind: .field(name: name), value: value)
        onChange(UIRecord(entries: entries))
    }

    private func remove(at index: Int) {
        var entries = record.entries
        guard index < entries.count else { return }
        entries.remove(at: index)
        onChange(UIRecord(entries: entries))
    }
}

struct ListEditorView: View {
    let items: [UIValue]
    let ownerName: String
    let onChange: (UIValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top) {
                    Text("\(index)").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                    ValueEditorView(value: item, ownerName: ownerName) { replace(at: index, value: $0) }
                    Button { remove(at: index) } label: { Image(systemName: "minus.circle").font(.system(size: 9)).foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                }
            }
            Button { onChange(.list(items + [.record(UIRecord())])) } label: {
                Label("Add item", systemImage: "plus.circle").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, 8)
    }

    private func replace(at index: Int, value: UIValue) {
        var copy = items
        guard index < copy.count else { return }
        copy[index] = value
        onChange(.list(copy))
    }

    private func remove(at index: Int) {
        var copy = items
        guard index < copy.count else { return }
        copy.remove(at: index)
        onChange(.list(copy))
    }
}

struct AnchorEditor: View {
    let value: UIValue
    let fields: [String]
    let onChange: (UIValue) -> Void

    var body: some View {
        let record = currentRecord
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(fields, id: \.self) { field in
                HStack(spacing: 4) {
                    Text(field).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                    CommitTextField(placeholder: "", value: fieldString(field, record: record)) { text in
                        commit(field: field, text: text)
                    }
                }
            }
        }
    }

    private var currentRecord: UIRecord {
        if case .record(let record) = value { return record }
        return UIRecord()
    }

    private func fieldString(_ field: String, record: UIRecord) -> String {
        guard let number = ValueReader.number(record.value(field)) else { return "" }
        return InspectorDefaults.numberString(number)
    }

    private func commit(field: String, text: String) {
        var entries = currentRecord.entries.filter { entry in
            if case .field(let name) = entry.kind, name == field { return false }
            return true
        }
        if let number = Double(text) {
            entries.append(UIRecordEntry(kind: .field(name: field), value: .number(number, isInteger: number.rounded() == number)))
        }
        onChange(.record(UIRecord(entries: entries)))
    }
}

struct CommitTextField: View {
    let placeholder: String
    let value: String
    let onCommit: (String) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .focused($focused)
            .onSubmit { onCommit(text) }
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(text) } }
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in if !focused { text = newValue } }
    }
}

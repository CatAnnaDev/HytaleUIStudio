import SwiftUI
import HytaleUICore

struct HierarchyNode: Identifiable {
    var id: String { path.map(String.init).joined(separator: ".") }
    var path: [Int]
    var element: UIElement
    var children: [HierarchyNode]?

    var title: String {
        let type = element.type.displayName.isEmpty ? "#slot" : element.type.displayName
        if let identifier = element.id {
            return "\(type)  #\(identifier)"
        }
        return type
    }
}

struct HierarchyView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hierarchy").font(.headline)
                Spacer()
                Button {
                    addSibling()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a Group at the root")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(selection: selectionBinding) {
                OutlineGroup(rootNodes(), children: \.children) { node in
                    Text(node.title)
                        .font(.system(size: 12))
                        .tag(node.path)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.removeElement(at: node.path)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var selectionBinding: Binding<[Int]?> {
        Binding(get: { store.selectedPath }, set: { store.selectedPath = $0 })
    }

    private func rootNodes() -> [HierarchyNode] {
        store.rootElements().enumerated().map { index, element in
            makeNode(element, path: [index])
        }
    }

    private func makeNode(_ element: UIElement, path: [Int]) -> HierarchyNode {
        let children = element.children.enumerated().map { index, child in
            makeNode(child, path: path + [index])
        }
        return HierarchyNode(path: path, element: element, children: children.isEmpty ? nil : children)
    }

    private func addSibling() {
        var statements = store.document.statements
        statements.append(.element(UIElement(type: .builtin("Group"), id: nil, members: [
            .property(UIProperty(name: "Anchor", value: .record(UIRecord(entries: [
                UIRecordEntry(kind: .field(name: "Width"), value: .number(200, isInteger: true)),
                UIRecordEntry(kind: .field(name: "Height"), value: .number(120, isInteger: true))
            ]))))
        ])))
        store.pushUndo()
        store.document = UIDocument(statements: statements)
        store.regenerateSource()
    }
}

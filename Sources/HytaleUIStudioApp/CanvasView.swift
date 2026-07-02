import SwiftUI
import HytaleUICore
import HytaleUIRender

private struct CanvasHit: Identifiable {
    let id = UUID()
    var path: [Int]?
    var rect: CGRect
    var typeName: String
    var isContainer: Bool
}

struct CanvasView: View {
    @ObservedObject var store: DocumentStore
    @GestureState private var moveTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            content(available: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color(white: 0.07))
                .contentShape(Rectangle())
                .onTapGesture { store.selectedPath = nil }
        }
    }

    @ViewBuilder
    private func content(available: CGSize) -> some View {
        let roots = store.resolvedRoots()
        if !roots.isEmpty {
            let size = canvasSize(roots)
            let laidRoots = roots.map { LayoutEngine().layout(root: $0, in: UIRect(x: 0, y: 0, width: size.width, height: size.height)) }
            let scale = fitScale(size: size, available: available)
            let image = SceneRenderer(textures: store.textures).render(roots: roots, size: size, scale: scale, backdrop: NSColor(white: 0.11, alpha: 1))
            let hits = laidRoots.flatMap { flatten($0, scale: scale) }

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                    .overlay(alignment: .topLeading) { hitLayer(hits) }
                    .overlay(alignment: .topLeading) { selectionLayer(hits, scale: scale) }
            }
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .dropDestination(for: String.self) { items, location in
                handleDrop(widgetNames: items, at: location, hits: hits, scale: scale)
            }
        } else {
            Text("No element to preview").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hitLayer(_ hits: [CanvasHit]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hits) { hit in
                if let path = hit.path {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: hit.rect.width, height: hit.rect.height)
                        .offset(x: hit.rect.minX, y: hit.rect.minY)
                        .onTapGesture { store.selectedPath = path }
                }
            }
        }
    }

    @ViewBuilder
    private func selectionLayer(_ hits: [CanvasHit], scale: CGFloat) -> some View {
        if let path = store.selectedPath, let hit = hits.first(where: { $0.path == path }) {
            let rect = hit.rect
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX + moveTranslation.width, y: rect.minY + moveTranslation.height)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(path: path, scale: scale))
                ForEach(handleSpecs, id: \.0) { spec in
                    handleView(spec: spec, rect: rect, path: path, scale: scale)
                }
            }
        }
    }

    private func moveGesture(path: [Int], scale: CGFloat) -> some Gesture {
        DragGesture()
            .updating($moveTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                adjustAnchor(path: path, deltas: ["Left": Double(value.translation.width / scale), "Top": Double(value.translation.height / scale)])
            }
    }

    private var handleSpecs: [(String, CGFloat, CGFloat)] {
        [("tl", 0, 0), ("tr", 1, 0), ("bl", 0, 1), ("br", 1, 1)]
    }

    private func handleView(spec: (String, CGFloat, CGFloat), rect: CGRect, path: [Int], scale: CGFloat) -> some View {
        let handleSize: CGFloat = 9
        let hx = rect.minX + moveTranslation.width + spec.1 * rect.width - handleSize / 2
        let hy = rect.minY + moveTranslation.height + spec.2 * rect.height - handleSize / 2
        return Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1))
            .frame(width: handleSize, height: handleSize)
            .offset(x: hx, y: hy)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        resize(path: path, corner: spec.0, translation: value.translation, scale: scale)
                    }
            )
    }

    private func resize(path: [Int], corner: String, translation: CGSize, scale: CGFloat) {
        guard let element = store.element(at: path) else { return }
        let anchor = anchorRecord(of: element)
        let dx = Double(translation.width / scale)
        let dy = Double(translation.height / scale)
        var deltas: [String: Double] = [:]
        let currentWidth = ValueReader.number(anchor.value("Width")) ?? sizeFallback(element).width
        let currentHeight = ValueReader.number(anchor.value("Height")) ?? sizeFallback(element).height
        switch corner {
        case "br":
            setAnchorField(path: path, name: "Width", value: max(4, currentWidth + dx))
            setAnchorField(path: path, name: "Height", value: max(4, currentHeight + dy))
        case "tr":
            setAnchorField(path: path, name: "Width", value: max(4, currentWidth + dx))
            setAnchorField(path: path, name: "Height", value: max(4, currentHeight - dy))
            deltas["Top"] = dy
        case "bl":
            setAnchorField(path: path, name: "Width", value: max(4, currentWidth - dx))
            setAnchorField(path: path, name: "Height", value: max(4, currentHeight + dy))
            deltas["Left"] = dx
        default:
            setAnchorField(path: path, name: "Width", value: max(4, currentWidth - dx))
            setAnchorField(path: path, name: "Height", value: max(4, currentHeight - dy))
            deltas["Left"] = dx
            deltas["Top"] = dy
        }
        if !deltas.isEmpty {
            adjustAnchor(path: path, deltas: deltas)
        }
    }

    private func sizeFallback(_ element: UIElement) -> UISize {
        if case .builtin(let name) = element.type, let widget = SemanticCatalog.widget(named: name) {
            return widget.defaultSize
        }
        return UISize(width: 100, height: 40)
    }

    private func handleDrop(widgetNames: [String], at location: CGPoint, hits: [CanvasHit], scale: CGFloat) -> Bool {
        guard let name = widgetNames.first, let widget = SemanticCatalog.widget(named: name) else { return false }
        let adjusted = CGPoint(x: location.x - 40, y: location.y - 40)
        let container = hits.filter { $0.isContainer && $0.path != nil && $0.rect.contains(adjusted) }
            .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })
        let targetPath = container?.path ?? store.selectedPath ?? store.rootElementPaths().first
        guard let path = targetPath, let containerRect = container?.rect else {
            appendWidget(widget, to: targetPath)
            return true
        }
        let localX = Double((adjusted.x - containerRect.minX) / scale)
        let localY = Double((adjusted.y - containerRect.minY) / scale)
        var members = widget.defaultMembers
        members.removeAll { if case .property(let property) = $0, property.name == "Anchor" { return true } else { return false } }
        members.insert(.property(UIProperty(name: "Anchor", value: .record(UIRecord(entries: [
            UIRecordEntry(kind: .field(name: "Left"), value: .number(localX.rounded(), isInteger: true)),
            UIRecordEntry(kind: .field(name: "Top"), value: .number(localY.rounded(), isInteger: true)),
            UIRecordEntry(kind: .field(name: "Width"), value: .number(widget.defaultSize.width, isInteger: true)),
            UIRecordEntry(kind: .field(name: "Height"), value: .number(widget.defaultSize.height, isInteger: true))
        ])))), at: 0)
        store.addChild(at: path, child: UIElement(type: .builtin(widget.name), id: nil, members: members))
        return true
    }

    private func appendWidget(_ widget: WidgetDefinition, to path: [Int]?) {
        if let path {
            store.addChild(at: path, child: UIElement(type: .builtin(widget.name), id: nil, members: widget.defaultMembers))
        }
    }

    private func adjustAnchor(path: [Int], deltas: [String: Double]) {
        guard let element = store.element(at: path) else { return }
        var record = anchorRecord(of: element)
        for (name, delta) in deltas {
            let current = ValueReader.number(record.value(name)) ?? 0
            record = upsert(record, name: name, value: .number((current + delta).rounded(), isInteger: true))
        }
        store.setProperty(at: path, name: "Anchor", value: .record(record))
    }

    private func setAnchorField(path: [Int], name: String, value: Double) {
        guard let element = store.element(at: path) else { return }
        let record = upsert(anchorRecord(of: element), name: name, value: .number(value.rounded(), isInteger: true))
        store.setProperty(at: path, name: "Anchor", value: .record(record))
    }

    private func anchorRecord(of element: UIElement) -> UIRecord {
        if case .record(let record)? = element.property("Anchor") { return record }
        return UIRecord()
    }

    private func upsert(_ record: UIRecord, name: String, value: UIValue) -> UIRecord {
        var entries = record.entries
        for index in entries.indices {
            if case .field(let fieldName) = entries[index].kind, fieldName == name {
                entries[index].value = value
                return UIRecord(entries: entries)
            }
        }
        entries.append(UIRecordEntry(kind: .field(name: name), value: value))
        return UIRecord(entries: entries)
    }

    private func canvasSize(_ roots: [ResolvedNode]) -> UISize {
        if roots.count == 1, case .record(let record)? = roots[0].property("Anchor"),
           let width = ValueReader.number(record.value("Width")),
           let height = ValueReader.number(record.value("Height")) {
            return UISize(width: width, height: height)
        }
        return UISize(width: 1920, height: 1080)
    }

    private func fitScale(size: UISize, available: CGSize) -> CGFloat {
        let usableWidth = max(80, available.width - 96)
        let usableHeight = max(80, available.height - 96)
        let scaleX = usableWidth / size.width
        let scaleY = usableHeight / size.height
        return min(2, max(0.1, min(scaleX, scaleY)))
    }

    private func flatten(_ root: LaidOutNode, scale: CGFloat) -> [CanvasHit] {
        let index = store.offsetIndex()
        func path(for node: ResolvedNode) -> [Int]? {
            let offset = node.sourceRange.start.offset
            var result: [Int]?
            for entry in index where entry.range.start.offset == offset {
                result = entry.path
            }
            return result
        }
        var hits: [CanvasHit] = []
        func walk(_ node: LaidOutNode) {
            let rect = CGRect(x: node.frame.x * scale, y: node.frame.y * scale, width: node.frame.width * scale, height: node.frame.height * scale)
            hits.append(CanvasHit(path: path(for: node.node), rect: rect, typeName: node.typeName, isContainer: SemanticCatalog.isContainer(node.typeName)))
            for child in node.children { walk(child) }
        }
        walk(root)
        return hits
    }
}

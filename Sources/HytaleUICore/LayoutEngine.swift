import Foundation

public struct LaidOutNode: Sendable {
    public var typeName: String
    public var id: String?
    public var componentName: String?
    public var frame: UIRect
    public var node: ResolvedNode
    public var children: [LaidOutNode]

    public init(node: ResolvedNode, frame: UIRect, children: [LaidOutNode]) {
        self.typeName = node.typeName
        self.id = node.id
        self.componentName = node.componentName
        self.frame = frame
        self.node = node
        self.children = children
    }
}

private struct AnchorSpec {
    var left: Double?
    var top: Double?
    var right: Double?
    var bottom: Double?
    var width: Double?
    var height: Double?
    var horizontal: Double?
    var vertical: Double?
}

public struct LayoutEngine {
    public init() {}

    public func layout(root: ResolvedNode, in viewport: UIRect) -> LaidOutNode {
        let anchor = anchorSpec(root)
        let frame = absoluteFrame(anchor: anchor, in: viewport, size: measure(root, maxWidth: viewport.width, maxHeight: viewport.height))
        return layoutNode(root, frame: frame)
    }

    private func layoutNode(_ node: ResolvedNode, frame: UIRect) -> LaidOutNode {
        let content = contentBox(node, frame: frame)
        let mode = layoutMode(node)
        let measured = node.children.map { measure($0, maxWidth: content.width, maxHeight: content.height) }
        let childFrames: [UIRect]
        if mode.isVerticalStack {
            childFrames = stack(node.children, measured: measured, in: content, vertical: true, mode: mode)
        } else if mode.isHorizontalStack {
            childFrames = stack(node.children, measured: measured, in: content, vertical: false, mode: mode)
        } else {
            childFrames = zip(node.children, measured).map { child, size in
                absoluteFrame(anchor: anchorSpec(child), in: content, size: size)
            }
        }
        var children: [LaidOutNode] = []
        for (child, childFrame) in zip(node.children, childFrames) {
            children.append(layoutNode(child, frame: childFrame))
        }
        return LaidOutNode(node: node, frame: frame, children: children)
    }

    private func stack(_ nodes: [ResolvedNode], measured: [UISize], in content: UIRect, vertical: Bool, mode: UILayoutMode) -> [UIRect] {
        let anchors = nodes.map { anchorSpec($0) }
        let flexes = nodes.map { flexWeight($0) }
        let mainExtent = vertical ? content.height : content.width
        let totalFlex = flexes.reduce(0, +)
        let stretchCross = !(mode == .middle || mode == .center || mode == .centerMiddle || mode == .middleCenter)

        var mainSizes: [Double] = []
        var fixedMain = 0.0
        for (index, anchor) in anchors.enumerated() {
            let margin = vertical ? ((anchor.top ?? 0) + (anchor.bottom ?? 0)) : ((anchor.left ?? 0) + (anchor.right ?? 0))
            let declared = vertical ? anchor.height : anchor.width
            let base = declared ?? (vertical ? measured[index].height : measured[index].width)
            let size = flexes[index] > 0 ? 0 : base
            mainSizes.append(size)
            fixedMain += size + margin
        }
        if totalFlex > 0 {
            let leftover = Swift.max(0, mainExtent - fixedMain)
            for index in mainSizes.indices where flexes[index] > 0 {
                mainSizes[index] = leftover * (flexes[index] / totalFlex)
            }
        }

        let usedMain = zip(mainSizes, anchors).reduce(0.0) { partial, pair in
            let margin = vertical ? ((pair.1.top ?? 0) + (pair.1.bottom ?? 0)) : ((pair.1.left ?? 0) + (pair.1.right ?? 0))
            return partial + pair.0 + margin
        }

        var cursor: Double
        switch mode {
        case .middle, .center, .centerMiddle, .middleCenter:
            cursor = (vertical ? content.minY : content.minX) + Swift.max(0, (mainExtent - usedMain) / 2)
        case .right, .bottomScrolling:
            cursor = (vertical ? content.maxY : content.maxX) - usedMain
        default:
            cursor = vertical ? content.minY : content.minX
        }

        var frames: [UIRect] = []
        for (index, anchor) in anchors.enumerated() {
            let marginStart = vertical ? (anchor.top ?? 0) : (anchor.left ?? 0)
            let marginEnd = vertical ? (anchor.bottom ?? 0) : (anchor.right ?? 0)
            let mainSize = mainSizes[index]
            let mainPos = cursor + marginStart

            let crossExtent = vertical ? content.width : content.height
            let crossOrigin = vertical ? content.minX : content.minY
            let crossDeclared = vertical ? anchor.width : anchor.height
            let crossMeasured = vertical ? measured[index].width : measured[index].height
            let crossMarginStart = vertical ? (anchor.left ?? 0) : (anchor.top ?? 0)
            let crossMarginEnd = vertical ? (anchor.right ?? 0) : (anchor.bottom ?? 0)
            let crossCenterOffset = vertical ? anchor.horizontal : anchor.vertical

            let crossSize: Double
            if let crossDeclared {
                crossSize = crossDeclared
            } else if stretchCross {
                crossSize = Swift.max(0, crossExtent - crossMarginStart - crossMarginEnd)
            } else {
                crossSize = crossMeasured
            }

            var crossPos: Double
            if let offset = crossCenterOffset {
                crossPos = crossOrigin + (crossExtent - crossSize) / 2 + offset
            } else if !stretchCross {
                crossPos = crossOrigin + (crossExtent - crossSize) / 2
            } else if crossDeclared != nil {
                if crossMarginEnd > 0 && crossMarginStart == 0 {
                    crossPos = crossOrigin + crossExtent - crossMarginEnd - crossSize
                } else if crossMarginStart == 0 && crossMarginEnd == 0 {
                    crossPos = crossOrigin + (crossExtent - crossSize) / 2
                } else {
                    crossPos = crossOrigin + crossMarginStart
                }
            } else {
                crossPos = crossOrigin + crossMarginStart
            }

            let frame = vertical
                ? UIRect(x: crossPos, y: mainPos, width: crossSize, height: mainSize)
                : UIRect(x: mainPos, y: crossPos, width: mainSize, height: crossSize)
            frames.append(frame)
            cursor += marginStart + mainSize + marginEnd
        }
        return frames
    }

    private func absoluteFrame(anchor: AnchorSpec, in container: UIRect, size: UISize) -> UIRect {
        let (x, width) = resolveAxis(minMargin: anchor.left, maxMargin: anchor.right, explicit: anchor.width, measured: size.width, center: anchor.horizontal, origin: container.minX, extent: container.width)
        let (y, height) = resolveAxis(minMargin: anchor.top, maxMargin: anchor.bottom, explicit: anchor.height, measured: size.height, center: anchor.vertical, origin: container.minY, extent: container.height)
        return UIRect(x: x, y: y, width: width, height: height)
    }

    private func resolveAxis(minMargin: Double?, maxMargin: Double?, explicit: Double?, measured: Double, center: Double?, origin: Double, extent: Double) -> (Double, Double) {
        if let explicit {
            if let center {
                return (origin + (extent - explicit) / 2 + center, explicit)
            }
            if let maxMargin, minMargin == nil {
                return (origin + extent - maxMargin - explicit, explicit)
            }
            if let minMargin {
                return (origin + minMargin, explicit)
            }
            return (origin + (extent - explicit) / 2, explicit)
        }
        if let minMargin, let maxMargin {
            return (origin + minMargin, Swift.max(0, extent - minMargin - maxMargin))
        }
        if let center {
            return (origin + (extent - measured) / 2 + center, measured)
        }
        if let minMargin {
            return (origin + minMargin, measured)
        }
        if let maxMargin {
            return (origin + extent - maxMargin - measured, measured)
        }
        return (origin, extent)
    }

    public func measure(_ node: ResolvedNode, maxWidth: Double, maxHeight: Double) -> UISize {
        let anchor = anchorSpec(node)
        let pad = padding(node)
        let mode = layoutMode(node)
        let innerMaxWidth = Swift.max(0, (anchor.width ?? maxWidth) - pad.horizontal)
        let innerMaxHeight = Swift.max(0, (anchor.height ?? maxHeight) - pad.vertical)

        var contentWidth = 0.0
        var contentHeight = 0.0

        if node.children.isEmpty {
            let leaf = leafSize(node, maxWidth: innerMaxWidth)
            contentWidth = leaf.width
            contentHeight = leaf.height
        } else if mode.isVerticalStack {
            var sum = 0.0
            var maxCross = 0.0
            for child in node.children {
                let childAnchor = anchorSpec(child)
                let size = measure(child, maxWidth: innerMaxWidth, maxHeight: innerMaxHeight)
                let mainMargin = (childAnchor.top ?? 0) + (childAnchor.bottom ?? 0)
                sum += (childAnchor.height ?? size.height) + mainMargin
                let crossMargin = (childAnchor.left ?? 0) + (childAnchor.right ?? 0)
                maxCross = Swift.max(maxCross, (childAnchor.width ?? size.width) + crossMargin)
            }
            contentHeight = sum
            contentWidth = maxCross
        } else if mode.isHorizontalStack {
            var sum = 0.0
            var maxCross = 0.0
            for child in node.children {
                let childAnchor = anchorSpec(child)
                let size = measure(child, maxWidth: innerMaxWidth, maxHeight: innerMaxHeight)
                let mainMargin = (childAnchor.left ?? 0) + (childAnchor.right ?? 0)
                sum += (childAnchor.width ?? size.width) + mainMargin
                let crossMargin = (childAnchor.top ?? 0) + (childAnchor.bottom ?? 0)
                maxCross = Swift.max(maxCross, (childAnchor.height ?? size.height) + crossMargin)
            }
            contentWidth = sum
            contentHeight = maxCross
        } else {
            for child in node.children {
                let childAnchor = anchorSpec(child)
                let size = measure(child, maxWidth: innerMaxWidth, maxHeight: innerMaxHeight)
                contentWidth = Swift.max(contentWidth, (childAnchor.left ?? 0) + (childAnchor.width ?? size.width) + (childAnchor.right ?? 0))
                contentHeight = Swift.max(contentHeight, (childAnchor.top ?? 0) + (childAnchor.height ?? size.height) + (childAnchor.bottom ?? 0))
            }
        }

        let width = anchor.width ?? (contentWidth + pad.horizontal)
        let height = anchor.height ?? (contentHeight + pad.vertical)
        return UISize(width: width, height: height)
    }

    private func leafSize(_ node: ResolvedNode, maxWidth: Double) -> UISize {
        if node.typeName == "Label", let text = labelText(node) {
            let style = labelMetrics(node)
            return textSize(text, fontSize: style.fontSize, wrap: style.wrap, maxWidth: maxWidth)
        }
        if let widget = SemanticCatalog.widget(named: node.typeName) {
            return widget.defaultSize
        }
        return UISize(width: 0, height: 0)
    }

    private func textSize(_ text: String, fontSize: Double, wrap: Bool, maxWidth: Double) -> UISize {
        let characterWidth = fontSize * 0.52
        let lineHeight = fontSize * 1.35
        let width = Double(text.count) * characterWidth
        if wrap && maxWidth > 0 && width > maxWidth {
            let lines = (width / maxWidth).rounded(.up)
            return UISize(width: maxWidth, height: lines * lineHeight)
        }
        return UISize(width: width, height: lineHeight)
    }

    private func labelText(_ node: ResolvedNode) -> String? {
        switch node.property("Text") {
        case .string(let text): return text
        case .binding(let path): return String(path.split(separator: ".").last ?? "")
        default: return nil
        }
    }

    private func labelMetrics(_ node: ResolvedNode) -> (fontSize: Double, wrap: Bool) {
        guard case .record(let record)? = styleRecord(node) else { return (15, false) }
        let fontSize = number(record.value("FontSize")) ?? 15
        var wrap = false
        if case .boolean(let flag)? = record.value("Wrap") { wrap = flag }
        return (fontSize, wrap)
    }

    private func styleRecord(_ node: ResolvedNode) -> UIValue? {
        if case .record(let record)? = node.property("Style") {
            return .record(record)
        }
        if case .constructor(_, let record)? = node.property("Style") {
            return .record(record)
        }
        return nil
    }

    private func contentBox(_ node: ResolvedNode, frame: UIRect) -> UIRect {
        let insets = padding(node)
        return UIRect(x: frame.x + insets.left, y: frame.y + insets.top, width: Swift.max(0, frame.width - insets.horizontal), height: Swift.max(0, frame.height - insets.vertical))
    }

    private func anchorSpec(_ node: ResolvedNode) -> AnchorSpec {
        var spec = AnchorSpec()
        guard case .record(let record)? = node.property("Anchor") else { return spec }
        if let full = number(record.value("Full")) {
            spec.left = full; spec.top = full; spec.right = full; spec.bottom = full
        }
        if let horizontal = number(record.value("Horizontal")) { spec.horizontal = horizontal }
        if let vertical = number(record.value("Vertical")) { spec.vertical = vertical }
        if let left = number(record.value("Left")) { spec.left = left }
        if let top = number(record.value("Top")) { spec.top = top }
        if let right = number(record.value("Right")) { spec.right = right }
        if let bottom = number(record.value("Bottom")) { spec.bottom = bottom }
        if let width = number(record.value("Width")) { spec.width = width }
        if let height = number(record.value("Height")) { spec.height = height }
        return spec
    }

    private func padding(_ node: ResolvedNode) -> UIEdgeInsets {
        guard let value = node.property("Padding") else { return .zero }
        if let uniform = number(value) {
            return UIEdgeInsets(left: uniform, top: uniform, right: uniform, bottom: uniform)
        }
        guard case .record(let record) = value else { return .zero }
        var insets = UIEdgeInsets()
        if let full = number(record.value("Full")) {
            insets = UIEdgeInsets(left: full, top: full, right: full, bottom: full)
        }
        if let horizontal = number(record.value("Horizontal")) {
            insets.left = horizontal; insets.right = horizontal
        }
        if let vertical = number(record.value("Vertical")) {
            insets.top = vertical; insets.bottom = vertical
        }
        if let left = number(record.value("Left")) { insets.left = left }
        if let top = number(record.value("Top")) { insets.top = top }
        if let right = number(record.value("Right")) { insets.right = right }
        if let bottom = number(record.value("Bottom")) { insets.bottom = bottom }
        return insets
    }

    private func layoutMode(_ node: ResolvedNode) -> UILayoutMode {
        if case .identifier(let name)? = node.property("LayoutMode") {
            return UILayoutMode(name: name)
        }
        return .none
    }

    private func flexWeight(_ node: ResolvedNode) -> Double {
        number(node.property("FlexWeight")) ?? 0
    }

    private func number(_ value: UIValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let number, _):
            return number
        case .grouping(let inner):
            return self.number(inner)
        case .unary(let op, let operand):
            guard let inner = self.number(operand) else { return nil }
            return op == .negate ? -inner : inner
        case .binary(let op, let lhs, let rhs):
            guard let left = self.number(lhs), let right = self.number(rhs) else { return nil }
            switch op {
            case .add: return left + right
            case .subtract: return left - right
            case .multiply: return left * right
            case .divide: return right == 0 ? nil : left / right
            }
        default:
            return nil
        }
    }
}

import Foundation
import AppKit
import HytaleUICore

public struct SceneRenderer {
    public var textures: TextureStore

    public init(textures: TextureStore) {
        self.textures = textures
    }

    public func layout(root: ResolvedNode, size: UISize) -> LaidOutNode {
        LayoutEngine().layout(root: root, in: UIRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    public func render(root: ResolvedNode, size: UISize, scale: CGFloat = 1, backdrop: NSColor? = nil) -> NSImage {
        render(roots: [root], size: size, scale: scale, backdrop: backdrop)
    }

    public func render(roots: [ResolvedNode], size: UISize, scale: CGFloat = 1, backdrop: NSColor? = nil) -> NSImage {
        let laidRoots = roots.map { layout(root: $0, size: size) }
        let pixelSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let image = NSImage(size: pixelSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.interpolationQuality = .none
            context.scaleBy(x: scale, y: scale)
            if let backdrop {
                backdrop.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            for laid in laidRoots {
                self.draw(node: laid, context: context)
            }
            return true
        }
        return image
    }

    public func render(laid: LaidOutNode, size: UISize, scale: CGFloat = 1, backdrop: NSColor? = nil) -> NSImage {
        let pixelSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let image = NSImage(size: pixelSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.interpolationQuality = .none
            context.scaleBy(x: scale, y: scale)
            if let backdrop {
                backdrop.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            self.draw(node: laid, context: context)
            return true
        }
        return image
    }

    private func draw(node: LaidOutNode, context: CGContext) {
        let frame = CGRect(x: node.frame.x, y: node.frame.y, width: node.frame.width, height: node.frame.height)
        drawBackground(for: node.node, in: frame, context: context)
        drawText(for: node.node, in: frame)
        for child in node.children {
            draw(node: child, context: context)
        }
    }

    private func drawBackground(for node: ResolvedNode, in frame: CGRect, context: CGContext) {
        switch nodeBackground(node) {
        case .color(let color):
            color.setFill()
            context.fill(frame)
        case .patch(let path, let insets):
            if let image = textures.image(for: path) {
                drawNineSlice(image: image, insets: insets, in: frame)
            } else {
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
                context.stroke(frame.insetBy(dx: 0.5, dy: 0.5), width: 1)
            }
        case .none:
            break
        }
    }

    private func nodeBackground(_ node: ResolvedNode) -> RenderBackground {
        if let value = node.property("Background") {
            let background = RenderReader.background(from: value)
            if case .none = background {} else { return background }
        }
        if let style = RenderReader.record(from: node.property("Style")) {
            if let def = RenderReader.record(from: style.value("Default")), let bg = def.value("Background") {
                return RenderReader.background(from: bg)
            }
            if style.value("TexturePath") != nil || style.value("Color") != nil {
                return RenderReader.background(from: node.property("Style"))
            }
        }
        return .none
    }

    private func drawText(for node: ResolvedNode, in frame: CGRect) {
        guard let raw = RenderReader.string(node.property("Text")), !raw.isEmpty else { return }
        let style = labelStyle(for: node)
        let text = style.uppercase ? raw.uppercased() : raw

        var font = NSFont.systemFont(ofSize: style.fontSize, weight: style.bold ? .bold : .regular)
        if style.italic, let italic = NSFontManager.shared.font(withFamily: font.familyName ?? "", traits: .italicFontMask, weight: 5, size: style.fontSize) {
            font = italic
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment
        paragraph.lineBreakMode = style.wrap ? .byWordWrapping : .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.color,
            .paragraphStyle: paragraph,
            .kern: style.letterSpacing
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let inset = frame.insetBy(dx: 3, dy: 1)
        guard inset.width > 1 else { return }
        let bounds = attributed.boundingRect(with: NSSize(width: inset.width, height: style.wrap ? inset.height : font.pointSize * 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
        var drawRect = inset
        if !style.wrap {
            let textHeight = min(bounds.height, inset.height)
            switch style.vertical {
            case .top: drawRect = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: textHeight)
            case .center: drawRect = CGRect(x: inset.minX, y: inset.minY + (inset.height - textHeight) / 2, width: inset.width, height: textHeight)
            case .bottom: drawRect = CGRect(x: inset.minX, y: inset.maxY - textHeight, width: inset.width, height: textHeight)
            }
        }
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func labelStyle(for node: ResolvedNode) -> LabelRenderStyle {
        if let style = RenderReader.record(from: node.property("Style")) {
            if style.value("FontSize") != nil || style.value("TextColor") != nil {
                return RenderReader.labelStyle(from: node.property("Style"))
            }
            if let def = RenderReader.record(from: style.value("Default")), let labelStyle = def.value("LabelStyle") {
                return RenderReader.labelStyle(from: labelStyle)
            }
        }
        return RenderReader.labelStyle(from: node.property("Style"))
    }

    private func drawNineSlice(image: NSImage, insets: UIEdgeInsets, in dst: CGRect) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        let scaleX = image.size.width > 0 ? pixelWidth / image.size.width : 1
        let scaleY = image.size.height > 0 ? pixelHeight / image.size.height : 1

        let left = min(CGFloat(insets.left), dst.width / 2)
        let right = min(CGFloat(insets.right), dst.width / 2)
        let top = min(CGFloat(insets.top), dst.height / 2)
        let bottom = min(CGFloat(insets.bottom), dst.height / 2)

        if left <= 0 && right <= 0 && top <= 0 && bottom <= 0 {
            NSImage(cgImage: cg, size: dst.size).draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            return
        }

        let sl = CGFloat(insets.left) * scaleX
        let sr = CGFloat(insets.right) * scaleX
        let st = CGFloat(insets.top) * scaleY
        let sb = CGFloat(insets.bottom) * scaleY

        let srcCols: [(CGFloat, CGFloat)] = [(0, sl), (sl, pixelWidth - sr - sl), (pixelWidth - sr, sr)]
        let srcRows: [(CGFloat, CGFloat)] = [(0, st), (st, pixelHeight - sb - st), (pixelHeight - sb, sb)]
        let dstCols: [(CGFloat, CGFloat)] = [(dst.minX, left), (dst.minX + left, dst.width - left - right), (dst.maxX - right, right)]
        let dstRows: [(CGFloat, CGFloat)] = [(dst.minY, top), (dst.minY + top, dst.height - top - bottom), (dst.maxY - bottom, bottom)]

        for row in 0..<3 {
            for col in 0..<3 {
                let srcRect = CGRect(x: srcCols[col].0, y: srcRows[row].0, width: max(0, srcCols[col].1), height: max(0, srcRows[row].1))
                let dstRect = CGRect(x: dstCols[col].0, y: dstRows[row].0, width: max(0, dstCols[col].1), height: max(0, dstRows[row].1))
                if srcRect.width < 1 || srcRect.height < 1 || dstRect.width <= 0 || dstRect.height <= 0 { continue }
                guard let sub = cg.cropping(to: srcRect) else { continue }
                NSImage(cgImage: sub, size: dstRect.size).draw(in: dstRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            }
        }
    }
}

public extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

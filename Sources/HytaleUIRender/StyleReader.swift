import Foundation
import AppKit
import HytaleUICore

public extension UIColor {
    var nsColor: NSColor {
        let c = components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}

public enum RenderBackground {
    case color(NSColor)
    case patch(path: String, insets: UIEdgeInsets)
    case none
}

public enum VerticalPlacement {
    case top
    case center
    case bottom
}

public struct LabelRenderStyle {
    public var fontSize: Double = 15
    public var color: NSColor = .white
    public var bold: Bool = false
    public var italic: Bool = false
    public var uppercase: Bool = false
    public var wrap: Bool = false
    public var alignment: NSTextAlignment = .left
    public var vertical: VerticalPlacement = .center
    public var letterSpacing: Double = 0
}

public enum RenderReader {
    public static func record(from value: UIValue?) -> UIRecord? {
        switch value {
        case .record(let record): return record
        case .constructor(_, let record): return record
        default: return nil
        }
    }

    public static func number(_ value: UIValue?) -> Double? {
        switch value {
        case .number(let n, _): return n
        case .grouping(let inner): return number(inner)
        case .unary(let op, let operand):
            guard let inner = number(operand) else { return nil }
            return op == .negate ? -inner : inner
        case .binary(let op, let lhs, let rhs):
            guard let l = number(lhs), let r = number(rhs) else { return nil }
            switch op {
            case .add: return l + r
            case .subtract: return l - r
            case .multiply: return l * r
            case .divide: return r == 0 ? nil : l / r
            }
        default: return nil
        }
    }

    public static func string(_ value: UIValue?) -> String? {
        switch value {
        case .string(let text): return text
        case .binding(let path): return bindingPlaceholder(path)
        default: return nil
        }
    }

    private static func bindingPlaceholder(_ path: String) -> String {
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        var spaced = ""
        for character in leaf {
            if character.isUppercase && !spaced.isEmpty {
                spaced.append(" ")
            }
            spaced.append(character)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    public static func bool(_ value: UIValue?) -> Bool {
        if case .boolean(let flag) = value { return flag }
        return false
    }

    public static func color(_ value: UIValue?) -> NSColor? {
        if case .color(let color) = value { return color.nsColor }
        return nil
    }

    public static func background(from value: UIValue?) -> RenderBackground {
        guard let record = record(from: value) else {
            if let color = color(value) { return .color(color) }
            return .none
        }
        if let path = string(record.value("TexturePath")) {
            return .patch(path: path, insets: borderInsets(record))
        }
        if let color = color(record.value("Color")) {
            return .color(color)
        }
        return .none
    }

    public static func borderInsets(_ record: UIRecord) -> UIEdgeInsets {
        var insets = UIEdgeInsets()
        if let border = number(record.value("Border")) {
            insets = UIEdgeInsets(left: border, top: border, right: border, bottom: border)
        }
        if let horizontal = number(record.value("HorizontalBorder")) {
            insets.left = horizontal; insets.right = horizontal
        }
        if let vertical = number(record.value("VerticalBorder")) {
            insets.top = vertical; insets.bottom = vertical
        }
        return insets
    }

    public static func labelStyle(from value: UIValue?) -> LabelRenderStyle {
        var style = LabelRenderStyle()
        guard let record = record(from: value) else { return style }
        if let size = number(record.value("FontSize")) { style.fontSize = size }
        if let color = color(record.value("TextColor")) { style.color = color }
        style.bold = bool(record.value("RenderBold"))
        style.italic = bool(record.value("RenderItalics"))
        style.uppercase = bool(record.value("RenderUppercase"))
        style.wrap = bool(record.value("Wrap"))
        if let spacing = number(record.value("LetterSpacing")) { style.letterSpacing = spacing }
        applyHorizontal(record.value("HorizontalAlignment"), to: &style)
        applyHorizontal(record.value("Alignment"), to: &style)
        applyVertical(record.value("VerticalAlignment"), to: &style)
        applyVertical(record.value("Alignment"), to: &style)
        return style
    }

    private static func applyHorizontal(_ value: UIValue?, to style: inout LabelRenderStyle) {
        guard case .identifier(let name)? = value else { return }
        switch name {
        case "Center", "CenterMiddle", "MiddleCenter": style.alignment = .center
        case "End", "Right": style.alignment = .right
        case "Start", "Left", "TopLeft": style.alignment = .left
        default: break
        }
    }

    private static func applyVertical(_ value: UIValue?, to style: inout LabelRenderStyle) {
        guard case .identifier(let name)? = value else { return }
        switch name {
        case "Center", "CenterMiddle", "MiddleCenter", "Middle": style.vertical = .center
        case "End", "Bottom": style.vertical = .bottom
        case "Start", "Top", "TopLeft": style.vertical = .top
        default: break
        }
    }
}

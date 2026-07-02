import AppKit
import HytaleUICore
import HytaleUIRender

enum SyntaxHighlighter {
    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    private static let defaultText = color(0xd4d4d4)
    private static let comment = color(0x6a9955)
    private static let string = color(0xce9178)
    private static let number = color(0xb5cea8)
    private static let keyword = color(0x569cd6)
    private static let macro = color(0xdcdcaa)
    private static let module = color(0x4ec9b0)
    private static let binding = color(0xc586c0)
    private static let identifierId = color(0x808080)
    private static let widgetType = color(0x4fc1ff)
    private static let propertyKey = color(0x9cdcfe)
    private static let enumValue = color(0xd7ba7d)
    private static let constructor = color(0x4ec9b0)
    private static let punctuation = color(0x9aa0a6)

    static func highlight(_ textStorage: NSTextStorage, font: NSFont) {
        let text = textStorage.string
        var lexer = Lexer(text)
        let tokens = lexer.tokenizeIncludingComments()
        let offsets = utf16OffsetMap(text)
        let length = offsets.last ?? 0

        textStorage.beginEditing()
        textStorage.setAttributes([.font: font, .foregroundColor: defaultText], range: NSRange(location: 0, length: length))
        for (index, token) in tokens.enumerated() where token.kind != .endOfFile {
            let next = nextMeaningful(tokens, after: index)
            guard let tokenColor = color(for: token, next: next) else { continue }
            let start = offsets[min(token.range.start.offset, offsets.count - 1)]
            let end = offsets[min(token.range.end.offset, offsets.count - 1)]
            if end > start, end <= length {
                textStorage.addAttribute(.foregroundColor, value: tokenColor, range: NSRange(location: start, length: end - start))
            }
        }
        textStorage.endEditing()
    }

    private static func nextMeaningful(_ tokens: [Token], after index: Int) -> Token? {
        var cursor = index + 1
        while cursor < tokens.count {
            let kind = tokens[cursor].kind
            if kind != .lineComment && kind != .blockComment { return tokens[cursor] }
            cursor += 1
        }
        return nil
    }

    private static func color(for token: Token, next: Token?) -> NSColor? {
        switch token.kind {
        case .lineComment, .blockComment:
            return comment
        case .string:
            return string
        case .number:
            return number
        case .boolean:
            return keyword
        case .macroRef:
            return macro
        case .moduleRef:
            return module
        case .binding:
            return binding
        case .hash:
            if let literal = colorLiteral(token.text) {
                return literal
            }
            return identifierId
        case .identifier:
            switch next?.kind {
            case .colon: return propertyKey
            case .leftParen: return constructor
            case .leftBrace, .hash: return widgetType
            default: return enumValue
            }
        case .leftBrace, .rightBrace, .leftParen, .rightParen, .leftBracket, .rightBracket, .colon, .semicolon, .comma, .equals, .dot, .spread, .plus, .minus, .star, .slash:
            return punctuation
        default:
            return nil
        }
    }

    private static func colorLiteral(_ text: String) -> NSColor? {
        var body = text
        var alpha: Double? = nil
        if let open = body.firstIndex(of: "(") {
            let inside = body[body.index(after: open)...].dropLast()
            alpha = Double(inside)
            body = String(body[body.startIndex..<open])
        }
        guard body.allSatisfy({ $0.isHexDigit }), [3, 4, 6, 8].contains(body.count) else { return nil }
        let components = UIColor(hex: body, alpha: alpha).components
        let brightness = 0.299 * components.red + 0.587 * components.green + 0.114 * components.blue
        let lifted = brightness < 0.25 ? 0.25 : 1.0
        return NSColor(srgbRed: CGFloat(max(components.red, components.red * lifted + (lifted == 1 ? 0 : 0.25))),
                       green: CGFloat(max(components.green, components.green * lifted + (lifted == 1 ? 0 : 0.25))),
                       blue: CGFloat(max(components.blue, components.blue * lifted + (lifted == 1 ? 0 : 0.25))),
                       alpha: 1)
    }

    private static func utf16OffsetMap(_ text: String) -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(text.count + 1)
        var running = 0
        for character in text {
            running += character.utf16.count
            offsets.append(running)
        }
        return offsets
    }
}

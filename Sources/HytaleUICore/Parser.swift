import Foundation

public struct Parser {
    private let tokens: [Token]
    private var index: Int = 0
    private var diagnostics: [Diagnostic] = []

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    public static func parse(_ source: String) -> ParseResult {
        var lexer = Lexer(source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let document = parser.parseDocument()
        let combined = lexer.diagnostics + parser.diagnostics
        return ParseResult(document: document, diagnostics: combined)
    }

    public static func parseValue(_ source: String) -> (value: UIValue, diagnostics: [Diagnostic])? {
        var lexer = Lexer(source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let value = parser.parseValue()
        if !parser.isAtEnd { return nil }
        return (value, lexer.diagnostics + parser.diagnostics)
    }

    private var current: Token {
        tokens[Swift.min(index, tokens.count - 1)]
    }

    private func peek(_ ahead: Int) -> Token {
        tokens[Swift.min(index + ahead, tokens.count - 1)]
    }

    private var isAtEnd: Bool {
        current.kind == .endOfFile
    }

    private func check(_ kind: TokenKind) -> Bool {
        current.kind == kind
    }

    private func checkNext(_ kind: TokenKind) -> Bool {
        peek(1).kind == kind
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = current
        if !isAtEnd { index += 1 }
        return token
    }

    @discardableResult
    private mutating func match(_ kind: TokenKind) -> Bool {
        if check(kind) {
            advance()
            return true
        }
        return false
    }

    @discardableResult
    private mutating func expect(_ kind: TokenKind, _ description: String) -> Token {
        if check(kind) {
            return advance()
        }
        diagnostics.append(Diagnostic(severity: .error, message: "Expected \(description) but found '\(current.text)'", range: current.range))
        return current
    }

    public mutating func parseDocument() -> UIDocument {
        var statements: [UIStatement] = []
        let start = current.range.start
        while !isAtEnd {
            while match(.semicolon) {}
            if isAtEnd { break }
            let before = index
            if let statement = parseTopLevelStatement() {
                statements.append(statement)
            }
            if index == before {
                advance()
            }
        }
        let end = current.range.end
        return UIDocument(statements: statements, range: SourceRange(start: start, end: end))
    }

    private mutating func parseTopLevelStatement() -> UIStatement? {
        if check(.moduleRef) && checkNext(.equals) {
            return parseImport()
        }
        if check(.macroRef) && checkNext(.equals) {
            return parseDefinition()
        }
        if let element = parseElement() {
            return .element(element)
        }
        return nil
    }

    private mutating func parseImport() -> UIStatement {
        let variableToken = advance()
        let start = variableToken.range.start
        expect(.equals, "'='")
        let value = parseValue()
        match(.semicolon)
        var path = ""
        if case .string(let text) = value {
            path = text
        } else {
            diagnostics.append(Diagnostic(severity: .warning, message: "Import path is not a string literal", range: variableToken.range))
        }
        return .importDeclaration(UIImport(variable: variableToken.text, path: path, range: SourceRange(start: start, end: current.range.start)))
    }

    private mutating func parseDefinition() -> UIStatement {
        let nameToken = advance()
        let start = nameToken.range.start
        expect(.equals, "'='")
        let value = parseValue()
        match(.semicolon)
        return .definition(UIDefinition(name: nameToken.text, value: value, range: SourceRange(start: start, end: current.range.start)))
    }

    private func startsElementType() -> Bool {
        check(.identifier) || check(.moduleRef) || check(.macroRef) || check(.hash)
    }

    private mutating func parseElement() -> UIElement? {
        guard startsElementType() else {
            diagnostics.append(Diagnostic(severity: .error, message: "Expected an element but found '\(current.text)'", range: current.range))
            return nil
        }
        let start = current.range.start
        var type: UIElementType = .slot
        if !check(.hash) {
            type = parseElementType()
        }
        var id: String? = nil
        if check(.hash) {
            id = advance().text
        }
        var members: [UIMember] = []
        if check(.leftBrace) {
            members = parseElementBody()
        } else {
            diagnostics.append(Diagnostic(severity: .error, message: "Expected '{' to open element body", range: current.range))
        }
        return UIElement(type: type, id: id, members: members, range: SourceRange(start: start, end: current.range.start))
    }

    private mutating func parseElementType() -> UIElementType {
        if check(.identifier) {
            return .builtin(advance().text)
        }
        return .component(parseReference())
    }

    private mutating func parseReference() -> UIReference {
        var module: String? = nil
        var name = ""
        if check(.moduleRef) {
            module = advance().text
            if match(.dot) {
                if check(.macroRef) {
                    name = advance().text
                } else {
                    diagnostics.append(Diagnostic(severity: .error, message: "Expected '@name' after '$\(module ?? "").'", range: current.range))
                }
            }
        } else {
            name = advance().text
        }
        var fields: [String] = []
        while check(.dot) && checkNext(.identifier) {
            advance()
            fields.append(advance().text)
        }
        return UIReference(module: module, name: name, fields: fields)
    }

    private mutating func parseElementBody() -> [UIMember] {
        expect(.leftBrace, "'{'")
        var members: [UIMember] = []
        while !check(.rightBrace) && !isAtEnd {
            while match(.semicolon) {}
            if check(.rightBrace) { break }
            let before = index
            if let member = parseMember() {
                members.append(member)
            }
            if index == before {
                advance()
            }
        }
        expect(.rightBrace, "'}'")
        return members
    }

    private mutating func parseMember() -> UIMember? {
        if check(.hash) {
            if let element = parseElement() {
                return .child(element)
            }
            return nil
        }
        if check(.macroRef) {
            if checkNext(.equals) {
                let nameToken = advance()
                let start = nameToken.range.start
                expect(.equals, "'='")
                let value = parseValue()
                match(.semicolon)
                return .parameter(UIProperty(name: nameToken.text, value: value, range: SourceRange(start: start, end: current.range.start)))
            }
            if let element = parseElement() {
                return .child(element)
            }
            return nil
        }
        if check(.moduleRef) {
            if let element = parseElement() {
                return .child(element)
            }
            return nil
        }
        if check(.identifier) {
            if checkNext(.colon) {
                let nameToken = advance()
                let start = nameToken.range.start
                expect(.colon, "':'")
                let value = parseValue()
                match(.semicolon)
                return .property(UIProperty(name: nameToken.text, value: value, range: SourceRange(start: start, end: current.range.start)))
            }
            if checkNext(.leftBrace) || checkNext(.hash) {
                if let element = parseElement() {
                    return .child(element)
                }
                return nil
            }
        }
        diagnostics.append(Diagnostic(severity: .error, message: "Unexpected token '\(current.text)' inside element body", range: current.range))
        return nil
    }

    private mutating func parseValue() -> UIValue {
        parseAdditive()
    }

    private mutating func parseAdditive() -> UIValue {
        var left = parseMultiplicative()
        while check(.plus) || check(.minus) {
            let op: UIBinaryOperator = check(.plus) ? .add : .subtract
            advance()
            let right = parseMultiplicative()
            left = .binary(op, lhs: left, rhs: right)
        }
        return left
    }

    private mutating func parseMultiplicative() -> UIValue {
        var left = parseUnary()
        while check(.star) || check(.slash) {
            let op: UIBinaryOperator = check(.star) ? .multiply : .divide
            advance()
            let right = parseUnary()
            left = .binary(op, lhs: left, rhs: right)
        }
        return left
    }

    private mutating func parseUnary() -> UIValue {
        if check(.minus) || check(.plus) {
            let op: UIUnaryOperator = check(.minus) ? .negate : .identity
            advance()
            return .unary(op, parseUnary())
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> UIValue {
        switch current.kind {
        case .number:
            let token = advance()
            let isInteger = !token.text.contains(".")
            return .number(Double(token.text) ?? 0, isInteger: isInteger)
        case .string:
            return .string(advance().text)
        case .boolean:
            return .boolean(advance().text == "true")
        case .hash:
            return .color(parseColor(advance().text))
        case .binding:
            return .binding(advance().text)
        case .identifier:
            return parseIdentifierValue()
        case .moduleRef, .macroRef:
            return parseReferenceValue()
        case .leftParen:
            return parseParenValue()
        case .leftBracket:
            return parseList()
        default:
            diagnostics.append(Diagnostic(severity: .error, message: "Expected a value but found '\(current.text)'", range: current.range))
            advance()
            return .identifier("")
        }
    }

    private mutating func parseIdentifierValue() -> UIValue {
        let start = current.range.start
        let name = advance().text
        if check(.leftParen) {
            let record = parseParenRecord()
            return .constructor(name: name, record: record)
        }
        if check(.leftBrace) || check(.hash) {
            var id: String? = nil
            if check(.hash) { id = advance().text }
            let members = parseElementBody()
            let element = UIElement(type: .builtin(name), id: id, members: members, range: SourceRange(start: start, end: current.range.start))
            return .element(element)
        }
        return .identifier(name)
    }

    private mutating func parseReferenceValue() -> UIValue {
        let start = current.range.start
        let reference = parseReference()
        if check(.leftBrace) || check(.hash) {
            var id: String? = nil
            if check(.hash) { id = advance().text }
            let members = parseElementBody()
            let element = UIElement(type: .component(reference), id: id, members: members, range: SourceRange(start: start, end: current.range.start))
            return .element(element)
        }
        return .reference(reference)
    }

    private mutating func parseList() -> UIValue {
        expect(.leftBracket, "'['")
        var items: [UIValue] = []
        while !check(.rightBracket) && !isAtEnd {
            items.append(parseValue())
            if !match(.comma) { break }
        }
        expect(.rightBracket, "']'")
        return .list(items)
    }

    private func looksLikeRecord() -> Bool {
        if peek(1).kind == .rightParen { return true }
        if peek(1).kind == .spread { return true }
        if peek(1).kind == .identifier && peek(2).kind == .colon { return true }
        return false
    }

    private mutating func parseParenValue() -> UIValue {
        if looksLikeRecord() {
            return .record(parseParenRecord())
        }
        expect(.leftParen, "'('")
        let expression = parseValue()
        expect(.rightParen, "')'")
        return .grouping(expression)
    }

    private mutating func parseParenRecord() -> UIRecord {
        expect(.leftParen, "'('")
        var entries: [UIRecordEntry] = []
        while !check(.rightParen) && !isAtEnd {
            let entryStart = current.range.start
            if match(.spread) {
                let value = parseValue()
                entries.append(UIRecordEntry(kind: .spread, value: value, range: SourceRange(start: entryStart, end: current.range.start)))
            } else if check(.identifier) {
                let name = advance().text
                expect(.colon, "':'")
                let value = parseValue()
                entries.append(UIRecordEntry(kind: .field(name: name), value: value, range: SourceRange(start: entryStart, end: current.range.start)))
            } else {
                diagnostics.append(Diagnostic(severity: .error, message: "Expected field name or spread but found '\(current.text)'", range: current.range))
                if !match(.comma) { break }
                continue
            }
            if !match(.comma) { break }
        }
        expect(.rightParen, "')'")
        return UIRecord(entries: entries)
    }

    private func parseColor(_ text: String) -> UIColor {
        var body = text
        if body.hasPrefix("#") { body.removeFirst() }
        if let open = body.firstIndex(of: "(") {
            let hex = String(body[body.startIndex..<open])
            let inside = body[body.index(after: open)...].dropLast()
            return UIColor(hex: hex, alpha: Double(inside))
        }
        return UIColor(hex: body, alpha: nil)
    }
}

import Foundation

public struct Lexer {
    private let scalars: [Character]
    private var offset: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    public private(set) var diagnostics: [Diagnostic] = []

    public init(_ source: String) {
        self.scalars = Array(source)
    }

    private var isAtEnd: Bool { offset >= scalars.count }

    private func peek(_ ahead: Int = 0) -> Character? {
        let index = offset + ahead
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    private var position: SourcePosition {
        SourcePosition(offset: offset, line: line, column: column)
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard offset < scalars.count else { return nil }
        let character = scalars[offset]
        offset += 1
        if character.isNewline {
            line += 1
            column = 1
        } else {
            column += 1
        }
        return character
    }

    private mutating func match(_ character: Character) -> Bool {
        guard peek() == character else { return false }
        advance()
        return true
    }

    public mutating func tokenize() -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = nextToken()
            if token.kind == .lineComment || token.kind == .blockComment {
                continue
            }
            tokens.append(token)
            if token.kind == .endOfFile { break }
        }
        return tokens
    }

    public mutating func tokenizeIncludingComments() -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = nextToken()
            tokens.append(token)
            if token.kind == .endOfFile { break }
        }
        return tokens
    }

    private mutating func nextToken() -> Token {
        skipWhitespace()
        let start = position
        guard let character = peek() else {
            return Token(kind: .endOfFile, text: "", range: SourceRange(start: start, end: start))
        }

        if character == "/" && peek(1) == "/" {
            return lineComment(start: start)
        }
        if character == "/" && peek(1) == "*" {
            return blockComment(start: start)
        }
        if character == "\"" {
            return stringLiteral(start: start)
        }
        if character == "#" {
            return hashToken(start: start)
        }
        if character == "$" {
            return prefixedIdentifier(kind: .moduleRef, start: start)
        }
        if character == "@" {
            return prefixedIdentifier(kind: .macroRef, start: start)
        }
        if character == "%" {
            return bindingToken(start: start)
        }
        if character == "." && peek(1) == "." && peek(2) == "." {
            advance(); advance(); advance()
            return finish(.spread, from: start)
        }
        if isDigit(character) {
            return numberLiteral(start: start)
        }
        if isIdentifierStart(character) {
            return identifierToken(start: start)
        }

        advance()
        switch character {
        case "{": return finish(.leftBrace, from: start)
        case "}": return finish(.rightBrace, from: start)
        case "(": return finish(.leftParen, from: start)
        case ")": return finish(.rightParen, from: start)
        case "[": return finish(.leftBracket, from: start)
        case "]": return finish(.rightBracket, from: start)
        case ":": return finish(.colon, from: start)
        case ";": return finish(.semicolon, from: start)
        case ",": return finish(.comma, from: start)
        case "=": return finish(.equals, from: start)
        case ".": return finish(.dot, from: start)
        case "+": return finish(.plus, from: start)
        case "-": return finish(.minus, from: start)
        case "*": return finish(.star, from: start)
        case "/": return finish(.slash, from: start)
        default:
            let range = SourceRange(start: start, end: position)
            diagnostics.append(Diagnostic(severity: .error, message: "Unexpected character '\(character)'", range: range))
            return Token(kind: .identifier, text: String(character), range: range)
        }
    }

    private func finish(_ kind: TokenKind, from start: SourcePosition) -> Token {
        let text = String(scalars[start.offset..<offset])
        return Token(kind: kind, text: text, range: SourceRange(start: start, end: position))
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace {
            advance()
        }
    }

    private mutating func lineComment(start: SourcePosition) -> Token {
        while let character = peek(), !character.isNewline {
            advance()
        }
        return finish(.lineComment, from: start)
    }

    private mutating func blockComment(start: SourcePosition) -> Token {
        advance()
        advance()
        while !isAtEnd {
            if peek() == "*" && peek(1) == "/" {
                advance(); advance()
                break
            }
            advance()
        }
        return finish(.blockComment, from: start)
    }

    private mutating func stringLiteral(start: SourcePosition) -> Token {
        advance()
        var value = ""
        while let character = peek() {
            if character == "\\" {
                advance()
                if let escaped = advance() {
                    switch escaped {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "r": value.append("\r")
                    case "\"": value.append("\"")
                    case "\\": value.append("\\")
                    default: value.append(escaped)
                    }
                }
                continue
            }
            if character == "\"" {
                advance()
                return Token(kind: .string, text: value, range: SourceRange(start: start, end: position))
            }
            if character.isNewline {
                break
            }
            value.append(character)
            advance()
        }
        let range = SourceRange(start: start, end: position)
        diagnostics.append(Diagnostic(severity: .error, message: "Unterminated string literal", range: range))
        return Token(kind: .string, text: value, range: range)
    }

    private mutating func hashToken(start: SourcePosition) -> Token {
        advance()
        var run = ""
        while let character = peek(), isIdentifierContinue(character) {
            run.append(character)
            advance()
        }
        let isColorRun = !run.isEmpty && run.allSatisfy { isHexDigit($0) } && [3, 4, 6, 8].contains(run.count)
        if isColorRun && peek() == "(" {
            let save = (offset, line, column)
            advance()
            var body = ""
            while let character = peek(), character != ")" {
                body.append(character)
                advance()
            }
            if peek() == ")", Double(body) != nil {
                advance()
                let text = run + "(" + body + ")"
                return Token(kind: .hash, text: text, range: SourceRange(start: start, end: position))
            }
            offset = save.0; line = save.1; column = save.2
        }
        if run.isEmpty {
            let range = SourceRange(start: start, end: position)
            diagnostics.append(Diagnostic(severity: .error, message: "Expected identifier or color after '#'", range: range))
            return Token(kind: .hash, text: "", range: range)
        }
        return Token(kind: .hash, text: run, range: SourceRange(start: start, end: position))
    }

    private mutating func prefixedIdentifier(kind: TokenKind, start: SourcePosition) -> Token {
        advance()
        var name = ""
        while let character = peek(), isIdentifierContinue(character) {
            name.append(character)
            advance()
        }
        return Token(kind: kind, text: name, range: SourceRange(start: start, end: position))
    }

    private mutating func bindingToken(start: SourcePosition) -> Token {
        advance()
        var name = ""
        while let character = peek(), isIdentifierContinue(character) || character == "." {
            name.append(character)
            advance()
        }
        return Token(kind: .binding, text: name, range: SourceRange(start: start, end: position))
    }

    private mutating func numberLiteral(start: SourcePosition) -> Token {
        while let character = peek(), isDigit(character) {
            advance()
        }
        if peek() == ".", let next = peek(1), isDigit(next) {
            advance()
            while let character = peek(), isDigit(character) {
                advance()
            }
        }
        return finish(.number, from: start)
    }

    private mutating func identifierToken(start: SourcePosition) -> Token {
        while let character = peek(), isIdentifierContinue(character) {
            advance()
        }
        let text = String(scalars[start.offset..<offset])
        if text == "true" || text == "false" {
            return Token(kind: .boolean, text: text, range: SourceRange(start: start, end: position))
        }
        return Token(kind: .identifier, text: text, range: SourceRange(start: start, end: position))
    }

    private func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    private func isHexDigit(_ character: Character) -> Bool {
        character.isHexDigit
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierContinue(_ character: Character) -> Bool {
        character == "_" || character.isLetter || isDigit(character)
    }
}

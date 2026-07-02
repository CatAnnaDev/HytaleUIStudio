import Foundation

public enum TokenKind: Sendable, Equatable {
    case identifier
    case number
    case string
    case boolean
    case binding
    case moduleRef
    case macroRef
    case hash
    case leftBrace
    case rightBrace
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case colon
    case semicolon
    case comma
    case equals
    case dot
    case spread
    case plus
    case minus
    case star
    case slash
    case lineComment
    case blockComment
    case endOfFile
}

public struct Token: Sendable {
    public var kind: TokenKind
    public var text: String
    public var range: SourceRange

    public init(kind: TokenKind, text: String, range: SourceRange) {
        self.kind = kind
        self.text = text
        self.range = range
    }
}

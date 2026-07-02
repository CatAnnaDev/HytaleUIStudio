import Foundation

public struct SourcePosition: Sendable, Hashable, Comparable {
    public var offset: Int
    public var line: Int
    public var column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }

    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        lhs.offset < rhs.offset
    }

    public static let zero = SourcePosition(offset: 0, line: 1, column: 1)
}

public struct SourceRange: Sendable, Hashable {
    public var start: SourcePosition
    public var end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    public static let unknown = SourceRange(start: .zero, end: .zero)

    public func union(_ other: SourceRange) -> SourceRange {
        SourceRange(start: Swift.min(start, other.start), end: Swift.max(end, other.end))
    }
}

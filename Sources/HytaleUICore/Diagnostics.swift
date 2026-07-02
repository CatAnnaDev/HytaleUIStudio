import Foundation

public enum DiagnosticSeverity: String, Sendable {
    case error
    case warning
}

public struct Diagnostic: Sendable, Error, CustomStringConvertible {
    public var severity: DiagnosticSeverity
    public var message: String
    public var range: SourceRange

    public init(severity: DiagnosticSeverity, message: String, range: SourceRange) {
        self.severity = severity
        self.message = message
        self.range = range
    }

    public var description: String {
        "\(severity.rawValue) at \(range.start.line):\(range.start.column): \(message)"
    }
}

public struct ParseResult: Sendable {
    public var document: UIDocument
    public var diagnostics: [Diagnostic]

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    public init(document: UIDocument, diagnostics: [Diagnostic]) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

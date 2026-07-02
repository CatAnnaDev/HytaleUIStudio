import Foundation

public final class AssetResolver {
    public var assetRoots: [URL]
    private let fileExists: (URL) -> Bool

    public init(assetRoots: [URL] = [], fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.assetRoots = assetRoots.map { $0.standardizedFileURL }
        self.fileExists = fileExists
    }

    public func resolve(importPath: String, from fileURL: URL) -> URL? {
        let relative = fileURL.deletingLastPathComponent().appendingPathComponent(importPath).standardizedFileURL
        if fileExists(relative) { return relative }

        if let root = assetRoots.first(where: { fileURL.path == $0.path || fileURL.path.hasPrefix($0.path + "/") }) {
            let relativePath = String(fileURL.path.dropFirst(root.path.count).drop(while: { $0 == "/" }))
            let directory = (relativePath as NSString).deletingLastPathComponent
            let combined = (directory as NSString).appendingPathComponent(importPath)
            let normalized = (combined as NSString).standardizingPath
            for candidate in assetRoots {
                let url = candidate.appendingPathComponent(normalized).standardizedFileURL
                if fileExists(url) { return url }
            }
        }

        let trimmed = importPath.drop(while: { $0 == "." || $0 == "/" })
        for candidate in assetRoots {
            let url = candidate.appendingPathComponent(String(trimmed)).standardizedFileURL
            if fileExists(url) { return url }
        }
        return relative
    }
}

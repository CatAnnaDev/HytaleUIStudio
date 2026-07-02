import Foundation
import AppKit

public final class TextureStore {
    private var images: [String: NSImage?] = [:]
    public private(set) var roots: [URL] = []

    public init(roots: [URL] = []) {
        self.roots = roots
    }

    public func setRoots(_ roots: [URL]) {
        if roots.map(\.path) != self.roots.map(\.path) {
            self.roots = roots
            images.removeAll()
        }
    }

    public func image(for path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        for candidate in candidateURLs(for: path) {
            if let image = NSImage(contentsOf: candidate) {
                images[path] = image
                return image
            }
        }
        images[path] = NSImage?.none
        return nil
    }

    private func candidateURLs(for path: String) -> [URL] {
        var variants: [String] = [path]
        if let dotIndex = path.lastIndex(of: ".") {
            let stem = String(path[path.startIndex..<dotIndex])
            let ext = String(path[dotIndex...])
            variants.insert(stem + "@2x" + ext, at: 0)
        }
        var urls: [URL] = []
        for root in roots {
            for variant in variants {
                urls.append(root.appendingPathComponent(variant))
            }
        }
        return urls
    }

    public static func textureRoots(documentURL: URL?, gameDataURL: URL?) -> [URL] {
        var roots: [URL] = []
        if let documentURL {
            var current = documentURL.deletingLastPathComponent()
            for _ in 0..<12 {
                let name = current.lastPathComponent
                if name == "UI" || name == "Interface" {
                    roots.append(current)
                    break
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
            roots.append(documentURL.deletingLastPathComponent())
        }
        if let gameDataURL {
            roots.append(gameDataURL.appendingPathComponent("Game/Interface"))
            roots.append(gameDataURL.appendingPathComponent("Editor/Interface"))
        }
        return roots
    }
}

import Foundation
import HytaleUICore

enum AppEnvironment {
    static let defaultGameDataCandidates: [String] = [
        "Library/Application Support/Hytale/install/release/package/game/latest/Client/Hytale.app/Contents/Resources/Data"
    ]

    static func detectGameDataURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for candidate in defaultGameDataCandidates {
            let url = home.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func textureRoots(for documentURL: URL?, gameDataURL: URL?) -> [URL] {
        var roots: [URL] = []
        if let documentURL {
            if let assetRoot = assetRoot(for: documentURL) {
                roots.append(assetRoot)
            }
            roots.append(documentURL.deletingLastPathComponent())
        }
        if let gameDataURL {
            roots.append(gameDataURL.appendingPathComponent("Game/Interface"))
            roots.append(gameDataURL.appendingPathComponent("Editor/Interface"))
        }
        return roots
    }

    static func assetRoot(for documentURL: URL) -> URL? {
        var current = documentURL.deletingLastPathComponent()
        for _ in 0..<12 {
            let name = current.lastPathComponent
            if name == "UI" || name == "Interface" {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }
}

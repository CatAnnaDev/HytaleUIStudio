import Foundation

public enum AssetRootFinder {
    public static func discover(near fileURL: URL?, extraWorkspaces: [URL] = []) -> [URL] {
        var workspaces = extraWorkspaces
        if let fileURL {
            let path = fileURL.path
            if let range = path.range(of: "/IdeaProjects/") {
                workspaces.append(URL(fileURLWithPath: String(path[..<range.upperBound])))
            } else {
                workspaces.append(fileURL.deletingLastPathComponent())
            }
        }
        var roots: [URL] = []
        var seen = Set<String>()
        for workspace in workspaces {
            for directory in commonUIDirectories(in: workspace) {
                let assetRoot = directory.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                if seen.insert(assetRoot.path).inserted {
                    roots.append(assetRoot)
                }
            }
        }
        return roots
    }

    private static func commonUIDirectories(in workspace: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: workspace.path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            workspace.path,
            "(", "-name", "node_modules", "-o", "-name", ".git", "-o", "-name", "build", "-o", "-name", ".gradle", "-o", "-name", ".idea", ")",
            "-prune", "-o",
            "-type", "d", "-path", "*/Common/UI", "-print"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
}

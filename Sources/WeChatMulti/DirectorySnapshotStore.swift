import Foundation
import WeChatMultiCore

/// Filesystem-backed `SnapshotStore`: each snapshot is a JSON file in
/// `~/Library/Application Support/WeChat Multi/Snapshots/`. The app is not
/// sandboxed, so Application Support is the natural home (survives clone
/// resets, which only touch `~/Applications/WeChat Multi/` and the containers).
final class DirectorySnapshotStore: SnapshotStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.directory = base.appendingPathComponent("WeChat Multi/Snapshots", isDirectory: true)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeSnapshot(_ data: Data, id: String) throws {
        try ensureDirectory()
        try data.write(to: directory.appendingPathComponent(id), options: .atomic)
    }

    func readSnapshot(id: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(id))
    }

    func snapshotIDs() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func removeSnapshot(id: String) throws {
        let url = directory.appendingPathComponent(id)
        // Already-gone counts as success (keeps prune idempotent).
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

import Foundation

/// Filesystem seam for settings snapshots — mirrors the `KeyValueStore` pattern
/// so the snapshot *policy* (when to write, what to prune, how to restore) is
/// pure and unit-testable against an in-memory fake, with no disk access.
///
/// `id` is an opaque snapshot identifier; the directory-backed implementation
/// in the app uses it as the on-disk filename.
public protocol SnapshotStore {
    func writeSnapshot(_ data: Data, id: String) throws
    func readSnapshot(id: String) throws -> Data
    func snapshotIDs() -> [String]          // unordered
    func removeSnapshot(id: String) throws
}

/// One snapshot's listing entry: its id plus the timestamp parsed from it.
public struct SnapshotInfo: Equatable {
    public let id: String
    public let createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// What `capture` decided to do — surfaced so callers (and tests) can tell a
/// real write apart from a deliberate no-op.
public enum SnapshotOutcome: Equatable {
    case wrote(id: String)
    case skippedUnchanged    // settings identical to the most recent snapshot
    case skippedThrottled    // changed, but too soon since the last snapshot
}

/// Automatic, rotating snapshots of the user's settings, layered on top of the
/// tested `SettingsBackup` codec. The app takes one on launch (throttled) and
/// one right before a risky import, so a bad import or accidental change is
/// recoverable from the most recent good state.
public enum SettingsSnapshots {
    public static let filePrefix = "wechatmulti-settings-"
    public static let fileExtension = "json"

    /// How many snapshots to keep before pruning the oldest.
    public static let defaultMaxSnapshots = 12
    /// Minimum spacing between periodic snapshots (6 hours).
    public static let defaultMinInterval: TimeInterval = 6 * 60 * 60

    // MARK: - ID ⇄ Date

    // UTC, fixed-width, lexicographically sortable in timestamp order.
    private static let stampFormat = "yyyyMMdd'T'HHmmss'Z'"

    private static func stampFormatter() -> DateFormatter {
        // DateFormatter isn't thread-safe; build a fresh one per call. These
        // operations are rare (launch / import), so the cost is irrelevant.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = stampFormat
        return f
    }

    /// Filename for a snapshot taken at `date`, e.g.
    /// `wechatmulti-settings-20260606T110000Z.json`.
    public static func makeID(at date: Date) -> String {
        "\(filePrefix)\(stampFormatter().string(from: date)).\(fileExtension)"
    }

    /// Parse the timestamp back out of a snapshot id, or nil if it doesn't match
    /// the expected `prefix + stamp + .json` shape.
    public static func date(fromID id: String) -> Date? {
        let suffix = ".\(fileExtension)"
        guard id.hasPrefix(filePrefix), id.hasSuffix(suffix) else { return nil }
        let start = id.index(id.startIndex, offsetBy: filePrefix.count)
        let end = id.index(id.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return stampFormatter().date(from: String(id[start..<end]))
    }

    // MARK: - Listing

    /// Snapshots newest-first. Ids that don't parse as timestamps are ignored,
    /// so stray files in the directory can't break the list.
    public static func list(in store: SnapshotStore) -> [SnapshotInfo] {
        store.snapshotIDs()
            .compactMap { id -> SnapshotInfo? in
                guard let date = date(fromID: id) else { return nil }
                return SnapshotInfo(id: id, createdAt: date)
            }
            .sorted { lhs, rhs in
                lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id > rhs.id
            }
    }

    // MARK: - Capture

    /// Write a snapshot of the current settings, then prune to `maxSnapshots`.
    ///
    /// - Skips with `.skippedUnchanged` when the meaningful settings are
    ///   identical to the most recent snapshot (no churn of duplicates).
    /// - When `minInterval` is non-nil, skips with `.skippedThrottled` if the
    ///   last snapshot is newer than that — used for the periodic path. Pass
    ///   `nil` (the default) to force a write, e.g. just before an import.
    @discardableResult
    public static func capture(from kv: KeyValueStore,
                               appVersion: String,
                               now: Date = Date(),
                               into store: SnapshotStore,
                               maxSnapshots: Int = defaultMaxSnapshots,
                               minInterval: TimeInterval? = nil) throws -> SnapshotOutcome {
        let newPayload = SettingsBackup.makePayload(store: kv, appVersion: appVersion, now: now)

        if let latest = list(in: store).first {
            if let data = try? store.readSnapshot(id: latest.id),
               let latestPayload = try? SettingsBackup.decode(data),
               SettingsBackup.sameSettings(latestPayload, newPayload) {
                return .skippedUnchanged
            }
            if let minInterval, now.timeIntervalSince(latest.createdAt) < minInterval {
                return .skippedThrottled
            }
        }

        let id = makeID(at: now)
        let data = try SettingsBackup.exportData(store: kv, appVersion: appVersion, now: now)
        try store.writeSnapshot(data, id: id)
        try prune(in: store, keeping: max(1, maxSnapshots))
        return .wrote(id: id)
    }

    /// Throttled + deduped convenience for the periodic (launch / timer) path.
    @discardableResult
    public static func captureIfDue(from kv: KeyValueStore,
                                    appVersion: String,
                                    now: Date = Date(),
                                    into store: SnapshotStore,
                                    maxSnapshots: Int = defaultMaxSnapshots,
                                    minInterval: TimeInterval = defaultMinInterval) throws -> SnapshotOutcome {
        try capture(from: kv, appVersion: appVersion, now: now, into: store,
                    maxSnapshots: maxSnapshots, minInterval: minInterval)
    }

    // MARK: - Prune

    /// Keep the newest `keeping` snapshots; remove the rest. A snapshot that's
    /// already gone is treated as success by the store, so this is idempotent.
    public static func prune(in store: SnapshotStore, keeping maxSnapshots: Int) throws {
        guard maxSnapshots >= 0 else { return }
        let all = list(in: store)
        guard all.count > maxSnapshots else { return }
        for stale in all[maxSnapshots...] {
            try store.removeSnapshot(id: stale.id)
        }
    }

    // MARK: - Restore

    /// Apply a chosen snapshot back onto the live settings store, reusing
    /// `SettingsBackup`'s validation + stale-path sanitization.
    public static func restore(id: String,
                               from store: SnapshotStore,
                               to kv: KeyValueStore,
                               pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws {
        let data = try store.readSnapshot(id: id)
        try SettingsBackup.restore(from: data, to: kv, pathExists: pathExists)
    }
}

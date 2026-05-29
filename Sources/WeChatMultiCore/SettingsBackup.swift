import Foundation

/// Export/import of user-tunable settings as JSON, so a new Mac install can
/// start from the previous machine's configuration. Decoupled from
/// `UserDefaults` (works against any `KeyValueStore`) and validated on import.
public enum SettingsBackup {
    public struct Payload: Codable, Equatable {
        public let version: Int
        public let exportedAt: String          // ISO-8601
        public let appVersion: String
        public let slotNames: [String: String] // slot index (string) → name
        public let slotOrder: [Int]
        public let wechatAppPath: String?       // nil = default auto-detection
        public let didShowOnboarding: Bool

        public static let currentVersion = 1

        public init(version: Int, exportedAt: String, appVersion: String,
                    slotNames: [String: String], slotOrder: [Int],
                    wechatAppPath: String?, didShowOnboarding: Bool) {
            self.version = version
            self.exportedAt = exportedAt
            self.appVersion = appVersion
            self.slotNames = slotNames
            self.slotOrder = slotOrder
            self.wechatAppPath = wechatAppPath
            self.didShowOnboarding = didShowOnboarding
        }
    }

    public enum ImportError: LocalizedError, Equatable {
        case malformed(String)
        case unsupportedSchema(found: Int, expected: Int)

        public var errorDescription: String? {
            switch self {
            case .malformed(let detail):
                return "This doesn't look like a valid WeChat Multi settings file. (\(detail))"
            case .unsupportedSchema(let found, let expected):
                return "Unsupported settings file (schema v\(found); this app expects v\(expected))."
            }
        }
    }

    // MARK: - Export

    public static func makePayload(store: KeyValueStore, appVersion: String, now: Date) -> Payload {
        let names = (store.dictionary(forKey: DefaultsKey.slotNames) as? [String: String]) ?? [:]
        let order = (store.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int]) ?? []
        return Payload(
            version: Payload.currentVersion,
            exportedAt: ISO8601DateFormatter().string(from: now),
            appVersion: appVersion,
            slotNames: names,
            slotOrder: order,
            wechatAppPath: store.string(forKey: DefaultsKey.customWeChatPath),
            didShowOnboarding: store.bool(forKey: DefaultsKey.didShowOnboarding)
        )
    }

    public static func exportData(store: KeyValueStore, appVersion: String, now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makePayload(store: store, appVersion: appVersion, now: now))
    }

    // MARK: - Import

    /// Decode + validate a settings payload. Throws `ImportError` (not a raw
    /// JSON error) so the UI can present something readable.
    public static func decode(_ data: Data) throws -> Payload {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ImportError.malformed("couldn't parse JSON")
        }
        guard payload.version == Payload.currentVersion else {
            throw ImportError.unsupportedSchema(found: payload.version,
                                                expected: Payload.currentVersion)
        }
        // Slot-name keys must be positive integers; reject obviously bogus files.
        for key in payload.slotNames.keys {
            guard let n = Int(key), n > 0 else {
                throw ImportError.malformed("invalid slot key “\(key)”")
            }
        }
        return payload
    }

    /// Apply a decoded payload to a store. Sanitizes: a custom WeChat path is
    /// only restored if it currently exists on disk (per `pathExists`), so a
    /// stale path from the old Mac doesn't leave the app pointing at nothing.
    public static func apply(_ payload: Payload,
                             to store: KeyValueStore,
                             pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        store.set(payload.slotNames, forKey: DefaultsKey.slotNames)
        store.set(payload.slotOrder, forKey: DefaultsKey.slotDisplayOrder)
        if let path = payload.wechatAppPath, pathExists(path) {
            store.set(path, forKey: DefaultsKey.customWeChatPath)
        } else {
            store.removeObject(forKey: DefaultsKey.customWeChatPath)
        }
        store.set(payload.didShowOnboarding, forKey: DefaultsKey.didShowOnboarding)
    }

    /// Convenience: decode + apply in one step.
    public static func restore(from data: Data,
                               to store: KeyValueStore,
                               pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws {
        let payload = try decode(data)
        apply(payload, to: store, pathExists: pathExists)
    }
}

import Foundation

/// A minimal key-value persistence seam. `UserDefaults` conforms to it as-is,
/// and tests use `InMemoryKeyValueStore` — so the whole settings layer can be
/// exercised deterministically without touching the real defaults database.
///
/// The method signatures intentionally mirror `UserDefaults` exactly, which is
/// why the conformance below has an empty body.
public protocol KeyValueStore: AnyObject {
    func string(forKey defaultName: String) -> String?
    func bool(forKey defaultName: String) -> Bool
    func integer(forKey defaultName: String) -> Int
    func array(forKey defaultName: String) -> [Any]?
    func dictionary(forKey defaultName: String) -> [String: Any]?
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}

/// Every UserDefaults key the app persists, in one place. Previously these
/// were string literals scattered across WeChatLauncher, AppDelegate, and
/// PreferencesView — easy to typo, impossible to grep reliably.
public enum DefaultsKey {
    public static let customWeChatPath   = "WeChatAppPath"
    public static let slotNames          = "SlotNames"
    public static let slotDisplayOrder   = "SlotDisplayOrder"
    public static let didShowOnboarding  = "DidShowFirstLaunchHint"
    public static let lastSeenVersion    = "LastSeenVersion"

    /// All keys — used by backup/restore to know the full settings surface.
    public static let all = [
        customWeChatPath, slotNames, slotDisplayOrder,
        didShowOnboarding, lastSeenVersion
    ]
}

/// Thread-safe in-memory `KeyValueStore` for tests (and any future preview /
/// ephemeral use). Mirrors `UserDefaults` semantics: `set(nil, …)` removes,
/// `bool`/`integer` return zero-values for absent or wrong-typed keys.
public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    public init(_ initial: [String: Any] = [:]) {
        storage = initial
    }

    public func string(forKey defaultName: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName] as? String
    }

    public func bool(forKey defaultName: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let b = storage[defaultName] as? Bool { return b }
        if let n = storage[defaultName] as? NSNumber { return n.boolValue }
        return false
    }

    public func integer(forKey defaultName: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let i = storage[defaultName] as? Int { return i }
        if let n = storage[defaultName] as? NSNumber { return n.intValue }
        return 0
    }

    public func array(forKey defaultName: String) -> [Any]? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName] as? [Any]
    }

    public func dictionary(forKey defaultName: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName] as? [String: Any]
    }

    public func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName]
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    public func removeObject(forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: defaultName)
    }
}

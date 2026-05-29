import Foundation

/// Thread-safe accessor for per-slot names and the display order, backed by any
/// `KeyValueStore`. The lock matters: names and order are dictionaries/arrays
/// persisted via read-modify-write, and the app mutates them from the main
/// thread (UI) *and* background queues (launch, health check, refresh). Without
/// serialization, two concurrent `setName` calls could clobber each other.
public final class SlotSettings {
    private let store: KeyValueStore
    private let lock = NSRecursiveLock()

    public init(store: KeyValueStore) {
        self.store = store
    }

    // MARK: - Names

    /// User-assigned name for a clone slot, or nil for the default. Slot 0
    /// (the original WeChat) is never named.
    public func name(forSlot slot: Int) -> String? {
        guard slot > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        return rawNames()["\(slot)"]
    }

    public func setName(_ name: String?, forSlot slot: Int) {
        guard slot > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        var dict = rawNames()
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            dict["\(slot)"] = name
        } else {
            dict.removeValue(forKey: "\(slot)")
        }
        store.set(dict, forKey: DefaultsKey.slotNames)
    }

    public func allNames() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return rawNames()
    }

    /// The display name to stamp into a clone's Info.plist: custom name, or
    /// "WeChat <slot>" fallback.
    public func displayName(forSlot slot: Int) -> String {
        name(forSlot: slot) ?? "WeChat \(slot)"
    }

    private func rawNames() -> [String: String] {
        (store.dictionary(forKey: DefaultsKey.slotNames) as? [String: String]) ?? [:]
    }

    // MARK: - Display order

    public func displayOrder() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return (store.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int]) ?? []
    }

    public func setDisplayOrder(_ order: [Int]) {
        lock.lock(); defer { lock.unlock() }
        store.set(order, forKey: DefaultsKey.slotDisplayOrder)
    }

    /// Atomically move a slot before a target in the persisted order.
    public func moveSlot(_ slot: Int, before target: Int?) {
        lock.lock(); defer { lock.unlock() }
        let current = (store.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int]) ?? []
        let next = SlotOrdering.reorder(current, moving: slot, before: target)
        store.set(next, forKey: DefaultsKey.slotDisplayOrder)
    }

    /// Ensure every slot in `present` is materialized in the saved order
    /// (appended in given sequence if missing), then return the resolved order.
    /// Used before the first manual move so an implicit "numeric order" becomes
    /// explicit and a single drag doesn't reshuffle everything.
    @discardableResult
    public func materialize(present: [Int]) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        var order = (store.array(forKey: DefaultsKey.slotDisplayOrder) as? [Int]) ?? []
        for slot in present where !order.contains(slot) {
            order.append(slot)
        }
        store.set(order, forKey: DefaultsKey.slotDisplayOrder)
        return order
    }
}

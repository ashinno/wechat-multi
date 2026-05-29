import Foundation

/// Pure functions for the popover's user-controlled display order. Slot numbers
/// stay tied to sandbox identity; only the *display* sequence is reorderable.
public enum SlotOrdering {
    /// Move `slot` to sit immediately before `target` in `order`. If `target`
    /// is nil (or not present), `slot` goes to the end. The moved slot is
    /// always removed from its old position first. No-op if slot == target.
    public static func reorder(_ order: [Int], moving slot: Int, before target: Int?) -> [Int] {
        guard slot != target else { return order }
        var next = order
        next.removeAll { $0 == slot }
        if let target, let idx = next.firstIndex(of: target) {
            next.insert(slot, at: idx)
        } else {
            next.append(slot)
        }
        return next
    }

    /// Produce the final ordered slot list for display: entries from
    /// `displayOrder` that are actually `available` come first (in saved
    /// order), then any remaining available slots appended in their given
    /// order. Filters out stale display-order entries automatically.
    public static func resolve(displayOrder: [Int], available: [Int]) -> [Int] {
        let availableSet = Set(available)
        var seen = Set<Int>()
        var result: [Int] = []

        for slot in displayOrder where availableSet.contains(slot) && !seen.contains(slot) {
            result.append(slot)
            seen.insert(slot)
        }
        for slot in available where !seen.contains(slot) {
            result.append(slot)
            seen.insert(slot)
        }
        return result
    }
}

namespace WeChatMulti.Core;

/// <summary>
/// Pure functions for the tray flyout's user-controlled display order. Port of
/// the macOS SlotOrdering. On Windows an "instance" is identified by an int id
/// (launch order in v1, or a stable wxid-derived id later).
/// </summary>
public static class InstanceOrdering
{
    /// <summary>
    /// Move <paramref name="id"/> to sit immediately before <paramref name="target"/>.
    /// If target is null (or absent), the id goes to the end. No-op if id == target.
    /// </summary>
    public static IReadOnlyList<int> Reorder(IReadOnlyList<int> order, int id, int? target)
    {
        if (target.HasValue && target.Value == id) return order.ToList();
        var next = order.Where(x => x != id).ToList();
        if (target.HasValue)
        {
            var idx = next.IndexOf(target.Value);
            if (idx >= 0) { next.Insert(idx, id); return next; }
        }
        next.Add(id);
        return next;
    }

    /// <summary>
    /// Final ordered id list for display: entries from <paramref name="displayOrder"/>
    /// that are actually <paramref name="available"/> first (in saved order, deduped),
    /// then any remaining available ids in their given order.
    /// </summary>
    public static IReadOnlyList<int> Resolve(IReadOnlyList<int> displayOrder, IReadOnlyList<int> available)
    {
        var availableSet = new HashSet<int>(available);
        var seen = new HashSet<int>();
        var result = new List<int>();

        foreach (var id in displayOrder)
            if (availableSet.Contains(id) && seen.Add(id))
                result.Add(id);

        foreach (var id in available)
            if (seen.Add(id))
                result.Add(id);

        return result;
    }
}

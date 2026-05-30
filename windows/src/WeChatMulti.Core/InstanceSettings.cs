using WeChatMulti.Core.Settings;

namespace WeChatMulti.Core;

/// <summary>
/// Thread-safe accessor for per-instance names and the display order, backed by
/// any <see cref="IKeyValueStore"/>. Port of the macOS SlotSettings — the lock
/// matters because names/order are read-modify-written from the UI thread and
/// background work.
/// </summary>
public sealed class InstanceSettings
{
    private readonly IKeyValueStore _store;
    private readonly object _lock = new();

    public InstanceSettings(IKeyValueStore store) => _store = store;

    // MARK: Names

    public string? Name(int id)
    {
        if (id <= 0) return null;
        lock (_lock)
            return RawNames().TryGetValue(id.ToString(), out var n) ? n : null;
    }

    public void SetName(int id, string? name)
    {
        if (id <= 0) return;
        lock (_lock)
        {
            var dict = new Dictionary<string, string>(RawNames());
            if (!string.IsNullOrWhiteSpace(name)) dict[id.ToString()] = name!;
            else dict.Remove(id.ToString());
            _store.SetStringDict(SettingsKey.InstanceNames, dict);
        }
    }

    public IReadOnlyDictionary<string, string> AllNames()
    {
        lock (_lock) return RawNames();
    }

    public string DisplayName(int id) => Name(id) ?? $"WeChat {id}";

    private IReadOnlyDictionary<string, string> RawNames() =>
        _store.GetStringDict(SettingsKey.InstanceNames) ?? new Dictionary<string, string>();

    // MARK: Display order

    public IReadOnlyList<int> DisplayOrder()
    {
        lock (_lock) return _store.GetIntArray(SettingsKey.InstanceOrder) ?? Array.Empty<int>();
    }

    public void SetDisplayOrder(IReadOnlyList<int> order)
    {
        lock (_lock) _store.SetIntArray(SettingsKey.InstanceOrder, order);
    }

    public void Move(int id, int? before)
    {
        lock (_lock)
        {
            var current = _store.GetIntArray(SettingsKey.InstanceOrder) ?? Array.Empty<int>();
            _store.SetIntArray(SettingsKey.InstanceOrder,
                               InstanceOrdering.Reorder(current, id, before));
        }
    }

    public IReadOnlyList<int> Materialize(IReadOnlyList<int> present)
    {
        lock (_lock)
        {
            var order = (_store.GetIntArray(SettingsKey.InstanceOrder) ?? Array.Empty<int>()).ToList();
            foreach (var id in present)
                if (!order.Contains(id)) order.Add(id);
            _store.SetIntArray(SettingsKey.InstanceOrder, order);
            return order;
        }
    }
}

using System.Collections.Concurrent;

namespace WeChatMulti.Core.Settings;

/// <summary>Thread-safe in-memory store for tests and previews.</summary>
public sealed class InMemoryKeyValueStore : IKeyValueStore
{
    private readonly ConcurrentDictionary<string, object> _storage = new();

    public string? GetString(string key) => _storage.TryGetValue(key, out var v) ? v as string : null;

    public bool GetBool(string key) => _storage.TryGetValue(key, out var v) && v is bool b && b;

    public IReadOnlyList<int>? GetIntArray(string key) =>
        _storage.TryGetValue(key, out var v) ? v as IReadOnlyList<int> : null;

    public IReadOnlyDictionary<string, string>? GetStringDict(string key) =>
        _storage.TryGetValue(key, out var v) ? v as IReadOnlyDictionary<string, string> : null;

    public void SetString(string key, string? value)
    {
        if (value is null) _storage.TryRemove(key, out _);
        else _storage[key] = value;
    }

    public void SetBool(string key, bool value) => _storage[key] = value;

    public void SetIntArray(string key, IReadOnlyList<int> value) => _storage[key] = value.ToList();

    public void SetStringDict(string key, IReadOnlyDictionary<string, string> value) =>
        _storage[key] = new Dictionary<string, string>(value);

    public void Remove(string key) => _storage.TryRemove(key, out _);
}

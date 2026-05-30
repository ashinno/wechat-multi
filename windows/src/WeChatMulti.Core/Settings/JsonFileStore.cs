using System.Text.Json;

namespace WeChatMulti.Core.Settings;

/// <summary>
/// JSON-file-backed <see cref="IKeyValueStore"/> (the Windows analog of
/// UserDefaults). Persists to a single JSON object — typically
/// <c>%APPDATA%\WeChat Multi\settings.json</c>. Thread-safe; writes are atomic
/// (temp file + move).
/// </summary>
public sealed class JsonFileStore : IKeyValueStore
{
    private readonly string _path;
    private readonly object _lock = new();
    private Dictionary<string, JsonElement> _data;

    private static readonly JsonSerializerOptions WriteOptions =
        new() { WriteIndented = true };

    public JsonFileStore(string path)
    {
        _path = path;
        _data = Load(path);
    }

    /// <summary>Default location: %APPDATA%\WeChat Multi\settings.json.</summary>
    public static JsonFileStore Default()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "WeChat Multi");
        Directory.CreateDirectory(dir);
        return new JsonFileStore(Path.Combine(dir, "settings.json"));
    }

    private static Dictionary<string, JsonElement> Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new();
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json) ?? new();
        }
        catch
        {
            return new();   // corrupt file → start clean rather than crash
        }
    }

    private void Persist()
    {
        var json = JsonSerializer.Serialize(_data, WriteOptions);
        var tmp = _path + ".tmp";
        File.WriteAllText(tmp, json);
        // Atomic replace.
        if (File.Exists(_path)) File.Replace(tmp, _path, null);
        else File.Move(tmp, _path);
    }

    private static JsonElement ToElement(object value) =>
        JsonSerializer.SerializeToElement(value);

    public string? GetString(string key)
    {
        lock (_lock)
            return _data.TryGetValue(key, out var e) && e.ValueKind == JsonValueKind.String
                ? e.GetString() : null;
    }

    public bool GetBool(string key)
    {
        lock (_lock)
            return _data.TryGetValue(key, out var e) && e.ValueKind == JsonValueKind.True;
    }

    public IReadOnlyList<int>? GetIntArray(string key)
    {
        lock (_lock)
        {
            if (!_data.TryGetValue(key, out var e) || e.ValueKind != JsonValueKind.Array) return null;
            var list = new List<int>();
            foreach (var item in e.EnumerateArray())
                if (item.TryGetInt32(out var n)) list.Add(n);
            return list;
        }
    }

    public IReadOnlyDictionary<string, string>? GetStringDict(string key)
    {
        lock (_lock)
        {
            if (!_data.TryGetValue(key, out var e) || e.ValueKind != JsonValueKind.Object) return null;
            var dict = new Dictionary<string, string>();
            foreach (var prop in e.EnumerateObject())
                if (prop.Value.ValueKind == JsonValueKind.String)
                    dict[prop.Name] = prop.Value.GetString()!;
            return dict;
        }
    }

    public void SetString(string key, string? value)
    {
        lock (_lock)
        {
            if (value is null) _data.Remove(key);
            else _data[key] = ToElement(value);
            Persist();
        }
    }

    public void SetBool(string key, bool value)
    {
        lock (_lock) { _data[key] = ToElement(value); Persist(); }
    }

    public void SetIntArray(string key, IReadOnlyList<int> value)
    {
        lock (_lock) { _data[key] = ToElement(value); Persist(); }
    }

    public void SetStringDict(string key, IReadOnlyDictionary<string, string> value)
    {
        lock (_lock) { _data[key] = ToElement(value); Persist(); }
    }

    public void Remove(string key)
    {
        lock (_lock) { _data.Remove(key); Persist(); }
    }
}

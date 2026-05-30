namespace WeChatMulti.Core.Settings;

/// <summary>
/// Minimal persistence seam (the macOS KeyValueStore analog). The app uses a
/// JSON-file-backed implementation; tests use <see cref="InMemoryKeyValueStore"/>.
/// </summary>
public interface IKeyValueStore
{
    string? GetString(string key);
    bool GetBool(string key);
    IReadOnlyList<int>? GetIntArray(string key);
    IReadOnlyDictionary<string, string>? GetStringDict(string key);
    void SetString(string key, string? value);
    void SetBool(string key, bool value);
    void SetIntArray(string key, IReadOnlyList<int> value);
    void SetStringDict(string key, IReadOnlyDictionary<string, string> value);
    void Remove(string key);
}

/// <summary>Every persisted settings key in one place (macOS DefaultsKey analog).</summary>
public static class SettingsKey
{
    public const string CustomWeChatPath  = "WeChatAppPath";
    public const string InstanceNames      = "InstanceNames";
    public const string InstanceOrder      = "InstanceDisplayOrder";
    public const string DidShowOnboarding  = "DidShowOnboarding";
    public const string LastSeenVersion    = "LastSeenVersion";

    public static readonly IReadOnlyList<string> All = new[]
    {
        CustomWeChatPath, InstanceNames, InstanceOrder, DidShowOnboarding, LastSeenVersion
    };
}

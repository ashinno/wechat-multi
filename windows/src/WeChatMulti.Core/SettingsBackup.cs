using System.Text.Json;
using System.Text.Json.Serialization;
using WeChatMulti.Core.Settings;

namespace WeChatMulti.Core;

/// <summary>
/// Export/import of user-tunable settings as JSON. Mirrors the macOS
/// SettingsBackup schema (version 1) so the discipline — and the shape — is
/// shared across platforms. Validated on import.
/// </summary>
public static class SettingsBackup
{
    public const int CurrentVersion = 1;

    public sealed record Payload(
        [property: JsonPropertyName("version")] int Version,
        [property: JsonPropertyName("exportedAt")] string ExportedAt,
        [property: JsonPropertyName("appVersion")] string AppVersion,
        [property: JsonPropertyName("instanceNames")] Dictionary<string, string> InstanceNames,
        [property: JsonPropertyName("instanceOrder")] List<int> InstanceOrder,
        [property: JsonPropertyName("wechatAppPath")] string? WeChatAppPath,
        [property: JsonPropertyName("didShowOnboarding")] bool DidShowOnboarding);

    public sealed class ImportException : Exception
    {
        public ImportException(string message) : base(message) { }
    }

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never
    };

    // MARK: Export

    public static Payload MakePayload(IKeyValueStore store, string appVersion, DateTimeOffset now) =>
        new(
            Version: CurrentVersion,
            ExportedAt: now.ToString("o"),
            AppVersion: appVersion,
            InstanceNames: new Dictionary<string, string>(
                store.GetStringDict(SettingsKey.InstanceNames) ?? new Dictionary<string, string>()),
            InstanceOrder: (store.GetIntArray(SettingsKey.InstanceOrder) ?? Array.Empty<int>()).ToList(),
            WeChatAppPath: store.GetString(SettingsKey.CustomWeChatPath),
            DidShowOnboarding: store.GetBool(SettingsKey.DidShowOnboarding));

    public static string ExportJson(IKeyValueStore store, string appVersion, DateTimeOffset now) =>
        JsonSerializer.Serialize(MakePayload(store, appVersion, now), Options);

    // MARK: Import

    public static Payload Decode(string json)
    {
        Payload? payload;
        try { payload = JsonSerializer.Deserialize<Payload>(json); }
        catch { throw new ImportException("This doesn't look like a valid WeChat Multi settings file (couldn't parse JSON)."); }

        if (payload is null)
            throw new ImportException("This doesn't look like a valid WeChat Multi settings file (empty).");
        if (payload.Version != CurrentVersion)
            throw new ImportException($"Unsupported settings file (schema v{payload.Version}; this app expects v{CurrentVersion}).");
        foreach (var key in payload.InstanceNames.Keys)
            if (!int.TryParse(key, out var n) || n <= 0)
                throw new ImportException($"Invalid instance key “{key}” in settings file.");
        return payload;
    }

    public static void Apply(Payload payload, IKeyValueStore store, Func<string, bool>? pathExists = null)
    {
        pathExists ??= File.Exists;
        store.SetStringDict(SettingsKey.InstanceNames, payload.InstanceNames);
        store.SetIntArray(SettingsKey.InstanceOrder, payload.InstanceOrder);
        if (payload.WeChatAppPath is { } path && pathExists(path))
            store.SetString(SettingsKey.CustomWeChatPath, path);
        else
            store.Remove(SettingsKey.CustomWeChatPath);
        store.SetBool(SettingsKey.DidShowOnboarding, payload.DidShowOnboarding);
    }

    public static void Restore(string json, IKeyValueStore store, Func<string, bool>? pathExists = null)
        => Apply(Decode(json), store, pathExists);
}

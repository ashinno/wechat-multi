using WeChatMulti.Core;
using WeChatMulti.Core.Settings;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class SettingsBackupTests
{
    private static InMemoryKeyValueStore Populated()
    {
        var s = new InMemoryKeyValueStore();
        s.SetStringDict(SettingsKey.InstanceNames,
            new Dictionary<string, string> { ["1"] = "Work", ["2"] = "Personal" });
        s.SetIntArray(SettingsKey.InstanceOrder, new[] { 2, 1 });
        s.SetString(SettingsKey.CustomWeChatPath, @"C:\Program Files\Tencent\WeChat\WeChat.exe");
        s.SetBool(SettingsKey.DidShowOnboarding, true);
        return s;
    }

    private static readonly DateTimeOffset FixedNow =
        DateTimeOffset.FromUnixTimeSeconds(1_700_000_000);

    [Fact]
    public void ExportImportRoundTrip()
    {
        var json = SettingsBackup.ExportJson(Populated(), "0.1.0", FixedNow);
        var dest = new InMemoryKeyValueStore();
        SettingsBackup.Restore(json, dest, _ => true);

        Assert.Equal("Work", dest.GetStringDict(SettingsKey.InstanceNames)!["1"]);
        Assert.Equal(new[] { 2, 1 }, dest.GetIntArray(SettingsKey.InstanceOrder));
        Assert.Equal(@"C:\Program Files\Tencent\WeChat\WeChat.exe",
                     dest.GetString(SettingsKey.CustomWeChatPath));
        Assert.True(dest.GetBool(SettingsKey.DidShowOnboarding));
    }

    [Fact]
    public void ExportIsDeterministicAndContainsSchema()
    {
        var json = SettingsBackup.ExportJson(Populated(), "0.1.0", FixedNow);
        Assert.Contains("\"version\": 1", json);
        Assert.Contains("\"appVersion\": \"0.1.0\"", json);
        Assert.Contains("\n", json);   // indented
    }

    [Fact]
    public void StaleCustomPathDroppedOnImport()
    {
        var json = SettingsBackup.ExportJson(Populated(), "0.1.0", FixedNow);
        var dest = new InMemoryKeyValueStore();
        SettingsBackup.Restore(json, dest, _ => false);   // new machine, path gone
        Assert.Null(dest.GetString(SettingsKey.CustomWeChatPath));
        Assert.Equal(new[] { 2, 1 }, dest.GetIntArray(SettingsKey.InstanceOrder));
    }

    [Fact]
    public void RejectsUnsupportedSchema()
    {
        var json = """
        {"version":99,"exportedAt":"2026-01-01T00:00:00Z","appVersion":"9.9",
         "instanceNames":{},"instanceOrder":[],"wechatAppPath":null,"didShowOnboarding":false}
        """;
        var ex = Assert.Throws<SettingsBackup.ImportException>(() => SettingsBackup.Decode(json));
        Assert.Contains("schema v99", ex.Message);
    }

    [Fact]
    public void RejectsMalformedJson()
        => Assert.Throws<SettingsBackup.ImportException>(() => SettingsBackup.Decode("not json"));

    [Fact]
    public void RejectsNonNumericInstanceKeys()
    {
        var json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","appVersion":"0.1.0",
         "instanceNames":{"work":"Work"},"instanceOrder":[],"wechatAppPath":null,"didShowOnboarding":true}
        """;
        Assert.Throws<SettingsBackup.ImportException>(() => SettingsBackup.Decode(json));
    }

    [Fact]
    public void NilCustomPathExportsAsNull()
    {
        var json = SettingsBackup.ExportJson(new InMemoryKeyValueStore(), "0.1.0", FixedNow);
        var payload = SettingsBackup.Decode(json);
        Assert.Null(payload.WeChatAppPath);
        Assert.Empty(payload.InstanceNames);
        Assert.Empty(payload.InstanceOrder);
    }
}

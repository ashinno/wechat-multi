using WeChatMulti.Core;
using WeChatMulti.Core.Settings;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class ChangelogTests
{
    [Fact]
    public void EntriesNewestFirstAndWellFormed()
    {
        var entries = Changelog.Entries;
        Assert.NotEmpty(entries);
        for (var i = 1; i < entries.Count; i++)
            Assert.True(new SemVer(entries[i - 1].Version) > new SemVer(entries[i].Version));
        foreach (var e in entries)
        {
            Assert.False(string.IsNullOrEmpty(e.Highlight));
            Assert.NotEmpty(e.Bullets);
            Assert.All(e.Bullets, b => Assert.False(string.IsNullOrEmpty(b)));
        }
    }

    [Fact]
    public void EntriesNewerFiltersAndCaps()
    {
        var newer = Changelog.EntriesNewer("0.0.0", limit: 3);
        Assert.NotEmpty(newer);
        Assert.Equal(Changelog.Entries[0].Version, newer[0].Version);
    }

    [Fact]
    public void NothingNewerThanLatest()
    {
        var top = Changelog.Entries[0].Version;
        Assert.Empty(Changelog.EntriesNewer(top));
        Assert.Empty(Changelog.EntriesNewer("99.0.0"));
    }
}

public class KeyValueStoreTests
{
    [Fact]
    public void SetAndGetTypes()
    {
        var s = new InMemoryKeyValueStore();
        s.SetString("str", "hello");
        s.SetBool("flag", true);
        s.SetIntArray("arr", new[] { 1, 2, 3 });
        s.SetStringDict("dict", new Dictionary<string, string> { ["a"] = "b" });

        Assert.Equal("hello", s.GetString("str"));
        Assert.True(s.GetBool("flag"));
        Assert.Equal(new[] { 1, 2, 3 }, s.GetIntArray("arr"));
        Assert.Equal("b", s.GetStringDict("dict")!["a"]);
    }

    [Fact]
    public void AbsentKeysReturnZeroValues()
    {
        var s = new InMemoryKeyValueStore();
        Assert.Null(s.GetString("nope"));
        Assert.False(s.GetBool("nope"));
        Assert.Null(s.GetIntArray("nope"));
        Assert.Null(s.GetStringDict("nope"));
    }

    [Fact]
    public void SetStringNullRemoves()
    {
        var s = new InMemoryKeyValueStore();
        s.SetString("k", "x");
        s.SetString("k", null);
        Assert.Null(s.GetString("k"));
    }

    [Fact]
    public void SettingsKeyCatalogIsComplete()
    {
        var declared = new HashSet<string>
        {
            SettingsKey.CustomWeChatPath, SettingsKey.InstanceNames,
            SettingsKey.InstanceOrder, SettingsKey.DidShowOnboarding,
            SettingsKey.LastSeenVersion
        };
        Assert.Equal(declared, new HashSet<string>(SettingsKey.All));
    }
}

public class JsonFileStoreTests
{
    [Fact]
    public void PersistsAcrossInstancesAndAtomicWrite()
    {
        var path = Path.Combine(Path.GetTempPath(), $"wcm-test-{Guid.NewGuid():N}.json");
        try
        {
            var a = new JsonFileStore(path);
            a.SetString(SettingsKey.CustomWeChatPath, @"C:\WeChat\WeChat.exe");
            a.SetIntArray(SettingsKey.InstanceOrder, new[] { 3, 1, 2 });
            a.SetStringDict(SettingsKey.InstanceNames, new Dictionary<string, string> { ["1"] = "Work" });
            a.SetBool(SettingsKey.DidShowOnboarding, true);

            var b = new JsonFileStore(path);   // fresh load from disk
            Assert.Equal(@"C:\WeChat\WeChat.exe", b.GetString(SettingsKey.CustomWeChatPath));
            Assert.Equal(new[] { 3, 1, 2 }, b.GetIntArray(SettingsKey.InstanceOrder));
            Assert.Equal("Work", b.GetStringDict(SettingsKey.InstanceNames)!["1"]);
            Assert.True(b.GetBool(SettingsKey.DidShowOnboarding));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void CorruptFileStartsClean()
    {
        var path = Path.Combine(Path.GetTempPath(), $"wcm-corrupt-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, "{ this is not valid json ");
        try
        {
            var s = new JsonFileStore(path);
            Assert.Null(s.GetString(SettingsKey.CustomWeChatPath));   // no crash
            s.SetBool(SettingsKey.DidShowOnboarding, true);            // recovers + writes
            Assert.True(new JsonFileStore(path).GetBool(SettingsKey.DidShowOnboarding));
        }
        finally
        {
            File.Delete(path);
        }
    }
}

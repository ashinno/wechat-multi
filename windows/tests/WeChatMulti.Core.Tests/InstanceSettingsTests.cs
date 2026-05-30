using WeChatMulti.Core;
using WeChatMulti.Core.Settings;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class InstanceSettingsTests
{
    private static InstanceSettings Make() => new(new InMemoryKeyValueStore());

    [Fact]
    public void SetGetClearName()
    {
        var s = Make();
        Assert.Null(s.Name(1));
        s.SetName(1, "Work");
        Assert.Equal("Work", s.Name(1));
        s.SetName(1, null);
        Assert.Null(s.Name(1));
    }

    [Fact]
    public void BlankNameClears()
    {
        var s = Make();
        s.SetName(1, "Work");
        s.SetName(1, "   ");
        Assert.Null(s.Name(1));
    }

    [Fact]
    public void IdZeroNeverNamed()
    {
        var s = Make();
        s.SetName(0, "Main");
        Assert.Null(s.Name(0));
        Assert.Empty(s.AllNames());
    }

    [Fact]
    public void DisplayNameFallback()
    {
        var s = Make();
        Assert.Equal("WeChat 2", s.DisplayName(2));
        s.SetName(2, "Personal");
        Assert.Equal("Personal", s.DisplayName(2));
    }

    [Fact]
    public void NamesPersistAcrossInstancesOfSameStore()
    {
        var store = new InMemoryKeyValueStore();
        new InstanceSettings(store).SetName(1, "Work");
        Assert.Equal("Work", new InstanceSettings(store).Name(1));
    }

    [Fact]
    public void OrderRoundTripAndMove()
    {
        var s = Make();
        Assert.Empty(s.DisplayOrder());
        s.SetDisplayOrder(new[] { 1, 2, 3 });
        s.Move(3, 1);
        Assert.Equal(new[] { 3, 1, 2 }, s.DisplayOrder());
    }

    [Fact]
    public void MaterializeAppendsMissingPreservingExisting()
    {
        var s = Make();
        s.SetDisplayOrder(new[] { 2 });
        Assert.Equal(new[] { 2, 0, 1, 3 }, s.Materialize(new[] { 0, 1, 2, 3 }));
    }

    [Fact]
    public void ConcurrentNameWritesDoNotCorrupt()
    {
        var s = Make();
        Parallel.For(0, 200, i => s.SetName((i % 10) + 1, $"name-{i}"));
        Assert.Equal(10, s.AllNames().Count);
        for (var id = 1; id <= 10; id++)
            Assert.StartsWith("name-", s.Name(id));
    }
}

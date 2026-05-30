using WeChatMulti.Core;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class SemVerTests
{
    [Theory]
    [InlineData("2.0.0", "1.8.0", true)]
    [InlineData("1.8.0", "1.7.9", true)]
    [InlineData("1.10.0", "1.9.0", true)]   // numeric, not lexical
    [InlineData("1.8.0", "1.8.0", false)]
    [InlineData("1.8.1", "1.8.0", true)]
    public void Ordering(string a, string b, bool aGreater)
        => Assert.Equal(aGreater, new SemVer(a) > new SemVer(b));

    [Fact]
    public void MissingComponentsAreZero()
    {
        Assert.Equal(new SemVer("1.8"), new SemVer("1.8.0"));
        Assert.Equal(new SemVer("1"), new SemVer("1.0.0"));
        Assert.True(new SemVer("1.8.1") > new SemVer("1.8"));
        Assert.False(new SemVer("1.8") > new SemVer("1.8.0"));
    }

    [Fact]
    public void Equality()
    {
        Assert.Equal(new SemVer("2.0.0"), new SemVer("2.0.0"));
        Assert.Equal(new SemVer("2.0"), new SemVer("2.0.0.0"));
        Assert.NotEqual(new SemVer("2.0.0"), new SemVer("2.0.1"));
    }

    [Fact]
    public void EqualVersionsShareHashCode()
        => Assert.Equal(new SemVer("1.8").GetHashCode(), new SemVer("1.8.0").GetHashCode());

    [Fact]
    public void LenientSuffixParsing()
    {
        Assert.Equal(new SemVer("1.8.0-beta"), new SemVer("1.8.0"));
        Assert.Equal(new SemVer("2.0.0rc1"), new SemVer("2.0.0"));
    }

    [Fact]
    public void IsNewerConvenience()
    {
        Assert.True(SemVer.IsNewer("2.0.0", "1.8.0"));
        Assert.False(SemVer.IsNewer("1.8.0", "2.0.0"));
        Assert.False(SemVer.IsNewer("1.8.0", "1.8.0"));
    }

    [Fact]
    public void SortStability()
    {
        var sorted = new[] { "1.7.0", "2.0.0", "1.8.0", "1.10.0", "1.9.5" }
            .Select(s => new SemVer(s)).OrderBy(v => v).Select(v => v.ToString());
        Assert.Equal(new[] { "1.7.0", "1.8.0", "1.9.5", "1.10.0", "2.0.0" }, sorted);
    }
}

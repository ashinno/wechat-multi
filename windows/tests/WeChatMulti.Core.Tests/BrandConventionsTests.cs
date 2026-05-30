using WeChatMulti.Core;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class BrandConventionsTests
{
    [Fact]
    public void DetectsWeChat3FromProcessNames()
    {
        var brand = BrandConventions.DetectFromProcessNames(
            new[] { "explorer", "WeChat", "WeChatAppEx" });
        Assert.NotNull(brand);
        Assert.Equal(WeChatBrand.WeChat3, brand!.Brand);
        Assert.Equal("WeChat Files", brand.DataFolderName);
    }

    [Fact]
    public void DetectsWeixin4FromProcessNames()
    {
        var brand = BrandConventions.DetectFromProcessNames(new[] { "Weixin", "chrome" });
        Assert.NotNull(brand);
        Assert.Equal(WeChatBrand.Weixin4, brand!.Brand);
        Assert.Equal("xwechat_files", brand.DataFolderName);
    }

    [Fact]
    public void ReturnsNullWhenNoWeChatRunning()
        => Assert.Null(BrandConventions.DetectFromProcessNames(new[] { "explorer", "chrome" }));

    [Fact]
    public void DetectionIsCaseInsensitive()
    {
        var brand = BrandConventions.DetectFromProcessNames(new[] { "wechat.exe" });
        // ".exe" suffix isn't stripped by detection (it compares raw names), so
        // this documents that callers pass bare process names; verify the
        // bare-name path works.
        Assert.Null(brand); // "wechat.exe" != "WeChat"
        var bare = BrandConventions.DetectFromProcessNames(new[] { "wechat" });
        Assert.Equal(WeChatBrand.WeChat3, bare!.Brand);
    }

    [Fact]
    public void IsMainProcessStripsExeAndIgnoresCase()
    {
        Assert.True(BrandConventions.WeChat3.IsMainProcess("WeChat.exe"));
        Assert.True(BrandConventions.WeChat3.IsMainProcess("wechat"));
        Assert.False(BrandConventions.WeChat3.IsMainProcess("WeChatAppEx.exe"));
        Assert.True(BrandConventions.Weixin4.IsMainProcess("Weixin.exe"));
        Assert.False(BrandConventions.Weixin4.IsMainProcess("WeChat.exe"));
    }

    [Fact]
    public void HelperSetsExcludeMainAndAreDistinct()
    {
        Assert.DoesNotContain(BrandConventions.WeChat3.MainProcessName,
                              BrandConventions.WeChat3.HelperProcessNames);
        Assert.DoesNotContain(BrandConventions.Weixin4.MainProcessName,
                              BrandConventions.Weixin4.HelperProcessNames);
    }
}

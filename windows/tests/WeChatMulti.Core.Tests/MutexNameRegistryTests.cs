using WeChatMulti.Core;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class MutexNameRegistryTests
{
    [Fact]
    public void KnownWeChat3NameMatchesExactly()
        => Assert.True(MutexNameRegistry.Matches(
            "_WeChat_App_Instance_Identity_Mutex_Name", WeChatBrand.WeChat3));

    [Fact]
    public void KnownNameMatchIsCaseInsensitive()
        => Assert.True(MutexNameRegistry.Matches(
            "_wechat_app_INSTANCE_identity_MUTEX_name", WeChatBrand.WeChat3));

    [Theory]
    [InlineData("Global\\WeChat_Instance_Lock")]
    [InlineData("Weixin_App_Instance_Mutex")]
    [InlineData("Some\\Weixin\\instance\\guard")]
    public void HeuristicAcceptsAppPlusLockNames(string name)
    {
        // Heuristic carries 4.x until a pinned name is confirmed in Phase 0.
        Assert.True(MutexNameRegistry.Matches(name, WeChatBrand.Weixin4));
    }

    [Theory]
    [InlineData("Local\\SM0:1234:WilStaging")]   // unrelated system mutant
    [InlineData("WeChatFileQueue")]               // mentions wechat but not a lock
    [InlineData("SomeOtherApp_Instance_Mutex")]   // a lock but not WeChat
    [InlineData("")]
    public void RejectsNonInstanceMutexes(string name)
    {
        Assert.False(MutexNameRegistry.Matches(name, WeChatBrand.WeChat3));
        Assert.False(MutexNameRegistry.Matches(name, WeChatBrand.Weixin4));
    }

    [Fact]
    public void Weixin4HasNoPinnedNameYet_ReliesOnHeuristic()
    {
        // Documents the Phase-0 gap: the 4.x known-list is intentionally empty.
        Assert.Empty(MutexNameRegistry.Known[WeChatBrand.Weixin4]);
    }
}

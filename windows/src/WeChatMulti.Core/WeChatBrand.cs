namespace WeChatMulti.Core;

/// <summary>Which WeChat line is installed. Drives every version-specific constant.</summary>
public enum WeChatBrand
{
    /// <summary>WeChat 3.x — WeChat.exe, "WeChat Files" data root.</summary>
    WeChat3,
    /// <summary>WeChat 4.x — Weixin.exe, "xwechat_files" data root.</summary>
    Weixin4
}

/// <summary>
/// The per-brand conventions from Appendix A of the Windows port plan. Kept as
/// data so adding a future variant is a one-line change, and so the detection /
/// exclusion logic is unit-testable without a live install.
///
/// Values flagged "VERIFY" in the plan are best-known starting points; Phase 0
/// confirms them against real installs.
/// </summary>
public sealed record BrandConventions(
    WeChatBrand Brand,
    string MainProcessName,          // without ".exe"
    IReadOnlyList<string> HelperProcessNames,
    string DataFolderName,
    string RegistrySubKey)
{
    public static readonly BrandConventions WeChat3 = new(
        Brand: WeChatBrand.WeChat3,
        MainProcessName: "WeChat",
        HelperProcessNames: new[]
        {
            "WeChatApp", "WeChatAppEx", "WeChatBrowser", "WeChatPlayer",
            "WeChatWeb", "WeChatUtility", "WeChatOCR"
        },
        DataFolderName: "WeChat Files",
        RegistrySubKey: @"Software\Tencent\WeChat");

    public static readonly BrandConventions Weixin4 = new(
        Brand: WeChatBrand.Weixin4,
        MainProcessName: "Weixin",
        HelperProcessNames: new[]
        {
            // VERIFY in Phase 0 — Weixin 4.x helper set (CEF/util helpers).
            "WeixinAppEx", "WeixinBrowser", "WeixinPlayer", "WeixinUtility", "mmcrashpad"
        },
        DataFolderName: "xwechat_files",
        RegistrySubKey: @"Software\Tencent\Weixin");

    public static readonly IReadOnlyList<BrandConventions> All = new[] { WeChat3, Weixin4 };

    /// <summary>
    /// Given the set of currently-running process names (without ".exe", any
    /// case), pick the brand whose <see cref="MainProcessName"/> is present.
    /// Returns null when no WeChat main process is running.
    /// </summary>
    public static BrandConventions? DetectFromProcessNames(IEnumerable<string> runningProcessNames)
    {
        var set = new HashSet<string>(runningProcessNames, StringComparer.OrdinalIgnoreCase);
        return All.FirstOrDefault(c => set.Contains(c.MainProcessName));
    }

    /// <summary>True if <paramref name="processName"/> is this brand's main process (not a helper).</summary>
    public bool IsMainProcess(string processName) =>
        string.Equals(StripExe(processName), MainProcessName, StringComparison.OrdinalIgnoreCase);

    private static string StripExe(string name) =>
        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;
}

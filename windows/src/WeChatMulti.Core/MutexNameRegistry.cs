namespace WeChatMulti.Core;

/// <summary>
/// The set of kernel-mutex names that WeChat uses for its single-instance lock,
/// per brand, plus a heuristic fallback for unseen versions. This is the
/// Windows analog of the macOS "clone trick may need revisiting after an
/// update": the whole maintenance surface for the singleton bypass is
/// concentrated here and fully unit-tested.
///
/// Names flagged VERIFY are confirmed in Phase 0 against real installs.
/// </summary>
public static class MutexNameRegistry
{
    /// <summary>Exact, version-pinned names take priority.</summary>
    public static readonly IReadOnlyDictionary<WeChatBrand, IReadOnlyList<string>> Known =
        new Dictionary<WeChatBrand, IReadOnlyList<string>>
        {
            // Widely cited across WeChat 3.x multi-instance tools. VERIFY on current build.
            [WeChatBrand.WeChat3] = new[] { "_WeChat_App_Instance_Identity_Mutex_Name" },
            // VERIFY in Phase 0 — likely a Weixin-based name; empty until confirmed,
            // so the heuristic below carries 4.x for now.
            [WeChatBrand.Weixin4] = Array.Empty<string>()
        };

    /// <summary>
    /// Does <paramref name="handleName"/> look like WeChat's instance mutex for
    /// <paramref name="brand"/>? Exact known names match first; otherwise a
    /// heuristic accepts a mutant whose name mentions wechat/weixin AND
    /// instance/mutex, so an unseen version still has a chance.
    /// </summary>
    public static bool Matches(string handleName, WeChatBrand brand)
    {
        if (string.IsNullOrEmpty(handleName)) return false;

        if (Known.TryGetValue(brand, out var known) &&
            known.Any(k => string.Equals(k, handleName, StringComparison.OrdinalIgnoreCase)))
            return true;

        var n = handleName.ToLowerInvariant();
        var mentionsApp = n.Contains("wechat") || n.Contains("weixin");
        var mentionsLock = n.Contains("instance") || n.Contains("mutex");
        return mentionsApp && mentionsLock;
    }
}

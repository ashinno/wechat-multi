namespace WeChatMulti.Core;

/// <summary>
/// Per-version changelog shown by the What's New window on first launch after a
/// version bump. Newest-first. Mirrors the macOS Core Changelog.
/// </summary>
public static class Changelog
{
    public sealed record Entry(string Version, string Highlight, IReadOnlyList<string> Bullets);

    public static readonly IReadOnlyList<Entry> Entries = new[]
    {
        new Entry(
            "0.1.0",
            "First Windows release",
            new[]
            {
                "Run multiple WeChat instances by releasing the single-instance lock",
                "Tray icon with a live running-instance count",
                "Launch a new instance with one click",
                "Built on a unit-tested core, mirroring the macOS app"
            })
    };

    /// <summary>Entries strictly newer than <paramref name="version"/>, newest-first, capped.</summary>
    public static IReadOnlyList<Entry> EntriesNewer(string version, int limit = 3)
    {
        var baseVer = new SemVer(version);
        return Entries
            .Where(e => new SemVer(e.Version) > baseVer)
            .Take(limit)
            .ToList();
    }
}

namespace WeChatMulti.Core;

/// <summary>
/// A lenient dotted-numeric version (e.g. "2.0.0", "1.8", "1.10.2"). Port of
/// the macOS Core SemVer: each dot component contributes its leading integer,
/// components are zero-padded for comparison, so 1.8 == 1.8.0 and 1.10 > 1.9.
/// </summary>
public readonly struct SemVer : IComparable<SemVer>, IEquatable<SemVer>
{
    public IReadOnlyList<int> Components { get; }

    public SemVer(string value)
    {
        Components = (value ?? string.Empty)
            .Split('.')
            .Select(part =>
            {
                var digits = new string(part.TakeWhile(char.IsDigit).ToArray());
                return int.TryParse(digits, out var n) ? n : 0;
            })
            .ToArray();
    }

    private int Component(int index) => index < Components.Count ? Components[index] : 0;

    public int CompareTo(SemVer other)
    {
        var count = Math.Max(Components.Count, other.Components.Count);
        for (var i = 0; i < count; i++)
        {
            var cmp = Component(i).CompareTo(other.Component(i));
            if (cmp != 0) return cmp;
        }
        return 0;
    }

    public bool Equals(SemVer other) => CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is SemVer s && Equals(s);

    public override int GetHashCode()
    {
        // Trailing zeros must not change the hash (1.8 == 1.8.0).
        var trimmed = Components.ToList();
        while (trimmed.Count > 1 && trimmed[^1] == 0) trimmed.RemoveAt(trimmed.Count - 1);
        var hash = new HashCode();
        foreach (var c in trimmed) hash.Add(c);
        return hash.ToHashCode();
    }

    public override string ToString() => string.Join('.', Components);

    public static bool operator >(SemVer a, SemVer b) => a.CompareTo(b) > 0;
    public static bool operator <(SemVer a, SemVer b) => a.CompareTo(b) < 0;
    public static bool operator >=(SemVer a, SemVer b) => a.CompareTo(b) >= 0;
    public static bool operator <=(SemVer a, SemVer b) => a.CompareTo(b) <= 0;
    public static bool operator ==(SemVer a, SemVer b) => a.Equals(b);
    public static bool operator !=(SemVer a, SemVer b) => !a.Equals(b);

    /// <summary>Convenience matching the macOS call site's intent.</summary>
    public static bool IsNewer(string a, string b) => new SemVer(a) > new SemVer(b);
}

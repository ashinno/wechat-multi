using System.Diagnostics;
using Microsoft.Win32;
using WeChatMulti.Core;

namespace WeChatMulti.Native;

/// <summary>
/// Locates the installed WeChat/Weixin executable and lists running main
/// processes. Implements <see cref="IProcessLister"/>. Most-robust-first
/// detection (Appendix A): a running instance's module path → registry →
/// default install locations.
/// </summary>
public sealed class WeChatLocator : IProcessLister
{
    public IReadOnlyList<WeChatProcess> RunningMainProcesses(BrandConventions brand)
    {
        var result = new List<WeChatProcess>();
        foreach (var p in Process.GetProcessesByName(brand.MainProcessName))
        {
            string? path = null;
            try { path = p.MainModule?.FileName; } catch { /* access denied — fine */ }
            result.Add(new WeChatProcess(p.Id, brand.MainProcessName, path));
        }
        return result;
    }

    /// <summary>All process names currently running (bare, no ".exe") — for brand detection.</summary>
    public static IReadOnlyList<string> AllProcessNames() =>
        Process.GetProcesses().Select(p => SafeName(p)).Where(n => n is not null).Select(n => n!).ToList();

    private static string? SafeName(Process p)
    {
        try { return p.ProcessName; } catch { return null; }
    }

    /// <summary>
    /// Resolve the WeChat exe path for a brand: a running instance's module
    /// path, else the registry install path, else common defaults.
    /// </summary>
    public string? FindExecutable(BrandConventions brand)
    {
        // 1. Running instance's module path (most reliable).
        var running = RunningMainProcesses(brand).FirstOrDefault(p => p.ExecutablePath is not null);
        if (running?.ExecutablePath is { } p1 && File.Exists(p1)) return p1;

        // 2. Registry install path.
        var installDir = ReadRegistryInstallPath(brand.RegistrySubKey);
        if (installDir is not null)
        {
            var p2 = Path.Combine(installDir, brand.MainProcessName + ".exe");
            if (File.Exists(p2)) return p2;
        }

        // 3. Default locations.
        foreach (var root in new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)
        })
        {
            var p3 = Path.Combine(root, "Tencent", brand.MainProcessName, brand.MainProcessName + ".exe");
            if (File.Exists(p3)) return p3;
        }
        return null;
    }

    private static string? ReadRegistryInstallPath(string subKey)
    {
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            try
            {
                using var key = hive.OpenSubKey(subKey);
                if (key?.GetValue("InstallPath") is string path && Directory.Exists(path))
                    return path;
            }
            catch { /* ignore */ }
        }
        return null;
    }
}

/// <summary>Implements <see cref="IProcessLauncher"/> via Process.Start.</summary>
public sealed class ProcessLauncher : IProcessLauncher
{
    public void Launch(string executablePath) =>
        Process.Start(new ProcessStartInfo(executablePath) { UseShellExecute = true });
}

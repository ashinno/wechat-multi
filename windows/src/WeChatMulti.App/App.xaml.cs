using System.Windows;

namespace WeChatMulti.App;

/// <summary>
/// Phase-1 tray app entry point. A real menu-bar-equivalent utility: no main
/// window, lives in the notification area. Full parity UI (flyout with instance
/// rows, Preferences, About, Onboarding, What's New) is Phase 3 — this skeleton
/// proves the Core + Native wiring end-to-end.
/// </summary>
public partial class App : Application
{
    private TrayController? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _tray = new TrayController();
        _tray.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }
}

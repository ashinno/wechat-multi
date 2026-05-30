using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;
using WeChatMulti.Core;
using WeChatMulti.Native;

namespace WeChatMulti.App;

/// <summary>
/// Owns the tray icon + context menu and wires user actions to the tested Core
/// orchestration (<see cref="InstanceLauncher"/>) over the Native interop.
/// Deliberately small — the value lives in Core; this is the thin shell.
/// </summary>
public sealed class TrayController : IDisposable
{
    private TaskbarIcon? _icon;
    private MenuItem? _headerItem;

    private readonly WeChatLocator _locator = new();
    private readonly HandleScanner _scanner = new();
    private readonly ProcessLauncher _launcher = new();

    public void Start()
    {
        var menu = BuildMenu();

        _icon = new TaskbarIcon
        {
            ToolTipText = "WeChat Multi",
            ContextMenu = menu,
            Icon = LoadTrayIcon()
        };
        // No XAML host → create the Win32 icon explicitly. Right-click opens
        // the context menu; left-click is wired to the same menu in Phase 3
        // (which replaces this with a richer flyout).
        _icon.ForceCreate();
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();

        _headerItem = new MenuItem { Header = "WeChat Multi", IsEnabled = false };
        menu.Items.Add(_headerItem);
        menu.Items.Add(new Separator());

        var launchItem = new MenuItem { Header = "Launch new instance" };
        launchItem.Click += (_, _) => LaunchNewInstance();
        menu.Items.Add(launchItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit WeChat Multi" };
        quitItem.Click += (_, _) => System.Windows.Application.Current.Shutdown();
        menu.Items.Add(quitItem);

        // Refresh the running count each time the menu opens.
        menu.Opened += (_, _) => UpdateHeader();
        return menu;
    }

    private void UpdateHeader()
    {
        var brand = DetectBrand();
        var count = brand is null ? 0 : _locator.RunningMainProcesses(brand).Count;
        if (_headerItem is not null)
            _headerItem.Header = count switch
            {
                0 => "No WeChat instances running",
                1 => "1 WeChat instance running",
                _ => $"{count} WeChat instances running"
            };
    }

    private BrandConventions? DetectBrand() =>
        BrandConventions.DetectFromProcessNames(WeChatLocator.AllProcessNames())
        // If nothing is running we can't detect from processes; fall back to
        // whichever brand we can locate on disk (prefer the newer Weixin).
        ?? BrandConventions.All.FirstOrDefault(b => _locator.FindExecutable(b) is not null);

    private void LaunchNewInstance()
    {
        var brand = DetectBrand();
        if (brand is null)
        {
            ShowMessage("WeChat not found",
                "Couldn't find WeChat or Weixin installed. Install it, then try again.");
            return;
        }
        var exe = _locator.FindExecutable(brand);
        if (exe is null)
        {
            ShowMessage("WeChat not found",
                $"Couldn't locate {brand.MainProcessName}.exe. Set its path in Preferences (coming soon).");
            return;
        }

        // Run off the UI thread — the handle scan spawns work.
        Task.Run(() =>
        {
            var orchestrator = new InstanceLauncher(_locator, _scanner, _scanner, _launcher);
            var result = orchestrator.LaunchAnother(brand, exe);

            System.Windows.Application.Current.Dispatcher.Invoke(() =>
            {
                switch (result.Status)
                {
                    case LaunchStatus.Launched:
                        _icon?.ShowNotification("WeChat Multi", "New instance launched.");
                        break;
                    case LaunchStatus.NeedsElevation:
                        if (Confirm("Administrator needed",
                                "Releasing WeChat's instance lock was blocked. Relaunch WeChat Multi as administrator and try again?"))
                            RelaunchElevated();
                        break;
                    case LaunchStatus.Failed:
                        ShowMessage("Could not launch", result.Detail ?? "Unknown error.");
                        break;
                }
            });
        });
    }

    private static void RelaunchElevated()
    {
        try
        {
            var exe = Process.GetCurrentProcess().MainModule?.FileName;
            if (exe is null) return;
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, Verb = "runas" });
            System.Windows.Application.Current.Shutdown();
        }
        catch { /* user declined UAC */ }
    }

    private static System.Drawing.Icon LoadTrayIcon()
    {
        var stream = System.Windows.Application
            .GetResourceStream(new Uri("pack://application:,,,/Assets/app.ico"))!.Stream;
        return new System.Drawing.Icon(stream);
    }

    private static void ShowMessage(string title, string body) =>
        MessageBox.Show(body, title, MessageBoxButton.OK, MessageBoxImage.Information);

    private static bool Confirm(string title, string body) =>
        MessageBox.Show(body, title, MessageBoxButton.YesNo, MessageBoxImage.Question)
            == MessageBoxResult.Yes;

    public void Dispose()
    {
        _icon?.Dispose();
        _icon = null;
    }
}

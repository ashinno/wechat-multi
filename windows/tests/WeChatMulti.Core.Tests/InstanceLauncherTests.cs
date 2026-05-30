using WeChatMulti.Core;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class InstanceLauncherTests
{
    // --- Fakes ---------------------------------------------------------------

    private sealed class FakeLister : IProcessLister
    {
        private readonly List<WeChatProcess> _procs;
        public FakeLister(params int[] pids) =>
            _procs = pids.Select(p => new WeChatProcess(p, "WeChat", @"C:\WeChat\WeChat.exe")).ToList();
        public IReadOnlyList<WeChatProcess> RunningMainProcesses(BrandConventions brand) => _procs;
    }

    private sealed class FakeScanner : IHandleScanner
    {
        private readonly List<MutexHandle> _handles;
        public FakeScanner(params MutexHandle[] handles) => _handles = handles.ToList();
        public IReadOnlyList<MutexHandle> FindInstanceMutexHandles(IReadOnlyList<int> pids, WeChatBrand brand) => _handles;
    }

    private sealed class FakeCloser : IMutexCloser
    {
        private readonly CloseOutcome _outcome;
        public List<MutexHandle> Closed { get; } = new();
        public FakeCloser(CloseOutcome outcome) => _outcome = outcome;
        public CloseResult CloseInTarget(MutexHandle handle)
        {
            if (_outcome == CloseOutcome.Closed) Closed.Add(handle);
            return new CloseResult(handle, _outcome);
        }
    }

    private sealed class FakeLauncher : IProcessLauncher
    {
        public int LaunchCount { get; private set; }
        public string? LastPath { get; private set; }
        private readonly bool _throw;
        public FakeLauncher(bool @throw = false) => _throw = @throw;
        public void Launch(string executablePath)
        {
            if (_throw) throw new InvalidOperationException("spawn failed");
            LaunchCount++;
            LastPath = executablePath;
        }
    }

    private static MutexHandle Handle(int pid) =>
        new(pid, 0x100, "_WeChat_App_Instance_Identity_Mutex_Name");

    // --- Tests ---------------------------------------------------------------

    [Fact]
    public void ClosesMutexInEveryOwnerThenLaunches()
    {
        var lister = new FakeLister(100, 200);
        var scanner = new FakeScanner(Handle(100), Handle(200));
        var closer = new FakeCloser(CloseOutcome.Closed);
        var launcher = new FakeLauncher();

        var result = new InstanceLauncher(lister, scanner, closer, launcher)
            .LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.Launched, result.Status);
        Assert.Equal(2, closer.Closed.Count);               // closed in both processes
        Assert.Equal(1, launcher.LaunchCount);
        Assert.Equal(@"C:\WeChat\WeChat.exe", launcher.LastPath);
    }

    [Fact]
    public void NoWeChatRunning_LaunchesFirstInstanceWithoutScanning()
    {
        var closer = new FakeCloser(CloseOutcome.Closed);
        var launcher = new FakeLauncher();
        var result = new InstanceLauncher(new FakeLister(), new FakeScanner(), closer, launcher)
            .LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.Launched, result.Status);
        Assert.Empty(closer.Closed);
        Assert.Equal(1, launcher.LaunchCount);
    }

    [Fact]
    public void AllClosesDenied_RequestsElevationAndDoesNotLaunch()
    {
        var launcher = new FakeLauncher();
        var result = new InstanceLauncher(
            new FakeLister(100),
            new FakeScanner(Handle(100)),
            new FakeCloser(CloseOutcome.AccessDenied),
            launcher).LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.NeedsElevation, result.Status);
        Assert.Equal(0, launcher.LaunchCount);   // doomed spawn avoided
    }

    [Fact]
    public void RunningButNoMutexFound_StillLaunches()
    {
        // Defensive: if the scanner finds nothing (unknown mutex name), we still
        // attempt the spawn — worst case WeChat just foregrounds the existing one.
        var launcher = new FakeLauncher();
        var result = new InstanceLauncher(
            new FakeLister(100), new FakeScanner(),
            new FakeCloser(CloseOutcome.Closed), launcher)
            .LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.Launched, result.Status);
        Assert.Equal(1, launcher.LaunchCount);
    }

    [Fact]
    public void LauncherThrows_ReturnsFailed()
    {
        var result = new InstanceLauncher(
            new FakeLister(100), new FakeScanner(Handle(100)),
            new FakeCloser(CloseOutcome.Closed), new FakeLauncher(@throw: true))
            .LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.Failed, result.Status);
        Assert.Equal("spawn failed", result.Detail);
    }

    [Fact]
    public void PartialCloseSuccess_StillLaunches()
    {
        // One close succeeds, even if others were denied → the lock is released,
        // so launching is correct (not an elevation case).
        var closer = new MixedCloser();
        var launcher = new FakeLauncher();
        var result = new InstanceLauncher(
            new FakeLister(100, 200), new FakeScanner(Handle(100), Handle(200)),
            closer, launcher).LaunchAnother(BrandConventions.WeChat3, @"C:\WeChat\WeChat.exe");

        Assert.Equal(LaunchStatus.Launched, result.Status);
        Assert.Equal(1, launcher.LaunchCount);
    }

    private sealed class MixedCloser : IMutexCloser
    {
        private int _n;
        public CloseResult CloseInTarget(MutexHandle handle) =>
            new(handle, _n++ == 0 ? CloseOutcome.Closed : CloseOutcome.AccessDenied);
    }
}

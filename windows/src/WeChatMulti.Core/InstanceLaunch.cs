namespace WeChatMulti.Core;

/// <summary>A running WeChat main process (from <see cref="IProcessLister"/>).</summary>
public sealed record WeChatProcess(int Pid, string ProcessName, string? ExecutablePath);

/// <summary>A handle to a candidate instance mutex inside a target process.</summary>
public sealed record MutexHandle(int Pid, ulong HandleValue, string Name);

public enum CloseOutcome { Closed, AccessDenied, Failed }
public sealed record CloseResult(MutexHandle Handle, CloseOutcome Outcome);

// --- Injected boundaries (Native implements; tests fake) -------------------

/// <summary>Lists running WeChat main processes (excludes helpers).</summary>
public interface IProcessLister
{
    IReadOnlyList<WeChatProcess> RunningMainProcesses(BrandConventions brand);
}

/// <summary>Enumerates mutant handles in the given PIDs and returns the ones that look like WeChat's lock.</summary>
public interface IHandleScanner
{
    IReadOnlyList<MutexHandle> FindInstanceMutexHandles(IReadOnlyList<int> pids, WeChatBrand brand);
}

/// <summary>Closes a mutex handle inside its owning process (DUPLICATE_CLOSE_SOURCE).</summary>
public interface IMutexCloser
{
    CloseResult CloseInTarget(MutexHandle handle);
}

/// <summary>Launches a new WeChat process from the given executable path.</summary>
public interface IProcessLauncher
{
    void Launch(string executablePath);
}

// --- The orchestrator -------------------------------------------------------

public enum LaunchStatus { Launched, NoWeChatRunning, NeedsElevation, Failed }

public sealed record LaunchResult(LaunchStatus Status, string? Detail = null);

/// <summary>
/// The pure orchestration of "launch one more instance": find processes, scan
/// for the instance mutex, close it in every owner, then spawn. All side
/// effects are behind injected interfaces, so this whole flow — including the
/// elevation decision and the "nothing running" edge — is unit-tested with
/// fakes, no WeChat or admin rights required.
/// </summary>
public sealed class InstanceLauncher
{
    private readonly IProcessLister _lister;
    private readonly IHandleScanner _scanner;
    private readonly IMutexCloser _closer;
    private readonly IProcessLauncher _launcher;

    public InstanceLauncher(IProcessLister lister, IHandleScanner scanner,
                            IMutexCloser closer, IProcessLauncher launcher)
    {
        _lister = lister;
        _scanner = scanner;
        _closer = closer;
        _launcher = launcher;
    }

    /// <summary>
    /// Releases the singleton lock and starts another instance.
    /// <paramref name="executablePath"/> is WeChat's main exe (from the locator).
    /// </summary>
    public LaunchResult LaunchAnother(BrandConventions brand, string executablePath)
    {
        var processes = _lister.RunningMainProcesses(brand);
        if (processes.Count == 0)
        {
            // No instance running → no mutex to release; just start the first one.
            try { _launcher.Launch(executablePath); return new(LaunchStatus.Launched); }
            catch (Exception ex) { return new(LaunchStatus.Failed, ex.Message); }
        }

        var pids = processes.Select(p => p.Pid).ToList();
        var handles = _scanner.FindInstanceMutexHandles(pids, brand.Brand);

        // Close in EVERY owner — a named mutex survives while any handle remains.
        var anyAccessDenied = false;
        var anyClosed = false;
        foreach (var h in handles)
        {
            var result = _closer.CloseInTarget(h);
            switch (result.Outcome)
            {
                case CloseOutcome.Closed: anyClosed = true; break;
                case CloseOutcome.AccessDenied: anyAccessDenied = true; break;
            }
        }

        // If we found handles but every close was access-denied, the caller
        // should retry elevated rather than spawn a doomed process.
        if (handles.Count > 0 && !anyClosed && anyAccessDenied)
            return new(LaunchStatus.NeedsElevation,
                       "Closing WeChat's instance lock was denied; try running elevated.");

        try { _launcher.Launch(executablePath); return new(LaunchStatus.Launched); }
        catch (Exception ex) { return new(LaunchStatus.Failed, ex.Message); }
    }
}

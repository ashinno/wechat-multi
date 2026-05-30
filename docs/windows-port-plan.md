# WeChat Multi — Windows Port Plan

> Status: **proposal**. This document plans a Windows version that mirrors the
> macOS app's UX and v2.0 "tested core" architecture, while accounting for the
> fundamentally different way multi-instance works on Windows.

---

## 1. Goal & scope

Ship a Windows tray utility that lets a user run several WeChat instances at
once, with the same feel as the macOS app: a tray icon, a flyout listing
running instances, one-click "launch another", named/colored instances,
preferences, about, onboarding, notifications, launch-at-login, auto-update.

**Non-goals (v1):** touching WeChat's internals beyond the singleton lock, chat
data manipulation, or anything that modifies the WeChat install.

---

## 2. The core pivot: how multi-instance differs from macOS

| | macOS (current) | Windows (this plan) |
|---|---|---|
| Singleton enforced by | `CFBundleIdentifier` (LaunchServices) | a **named kernel mutex** |
| Our bypass | clone `.app`, give each a unique bundle ID → own sandbox container | **close the mutex handle** in running WeChat processes, then launch again |
| Per-instance artifact | a numbered, on-disk cloned bundle (durable identity) | **none** — instances are just processes (ephemeral identity) |
| Data isolation | automatic (sandbox container per bundle ID) | WeChat already stores chat data per-account (`wxid`) in a shared folder, so accounts coexist |
| "It broke after a WeChat update" risk | clone/sign trick may need revisiting | **mutex name may change between versions** — same risk class |

The macOS clone trick has no Windows analog and is **not** needed: on Windows
all instances share one install and one data root, and WeChat already
partitions chat data by `wxid`. The only thing stopping a second process is the
mutex.

---

## 3. The mechanism in detail

WeChat for Windows creates a **named mutex** on startup (historically
`_WeChat_App_Instance_Identity_Mutex_Name`; **version-dependent** — must be
verified against current builds and maintained as a list, see Risks). The
second launch opens the existing mutex, foregrounds the running window, and
exits.

A named mutex is one kernel object shared by name; it lives until **every**
handle to it is closed. So to allow a new instance:

```
launchNewInstance():
  pids   = enumerate running WeChat main processes        // WeChat.exe / Weixin.exe
  handles = NtQuerySystemInformation(SystemExtendedHandleInformation)
            filtered to type "Mutant" owned by pids
  for h in handles:
      name = NtQueryObject(h, ObjectNameInformation)      // run on worker w/ timeout
      if matchesWeChatInstanceMutex(name):                // known-list + heuristic
          DuplicateHandle(targetProc, h, ourProc, &dup,
                          0, false, DUPLICATE_CLOSE_SOURCE) // closes it in target
  Process.Start(weChatExePath)                            // new instance spawns
```

Key facts that shape the design:

- **Close it in *all* running WeChat processes** before spawning, or the kernel
  object survives (refcount > 0) and the new process still sees it.
- **Privileges:** we need `OpenProcess(PROCESS_DUP_HANDLE)` on the WeChat
  processes. Same-user / same-integrity usually suffices; if WeChat runs at a
  different integrity level, we may need an **elevated (admin) manifest** → a
  UAC prompt. Must be measured on real builds; prefer `asInvoker` with an
  elevation fallback only when a close fails with access-denied.
- **`NtQueryObject` can hang** on certain handle types — query names on a worker
  thread with a timeout (well-known gotcha).
- **No external tools.** A quick prototype can shell out to Sysinternals
  `handle64.exe`, but its EULA forbids redistribution — production reimplements
  the NT calls in-process (also removes a dependency and AV surface).

---

## 4. Tech stack

**Recommendation: C# / .NET 8 (LTS), self-contained, with P/Invoke.**

- Mirrors the Swift/AppKit role: native, single-exe AOT/self-contained,
  first-class Win32 interop, mature tray + windowing.
- **UI: WPF** for stability and the cleanest tray story, themed to feel modern
  (Win11 Mica/Acrylic backdrop, rounded corners, Fluent controls). WinUI 3 is
  the more modern alternative but its tray/flyout-from-tray story is rougher;
  WPF + a tray library is lower-risk for v1.
- **Tray:** `H.NotifyIcon` (WPF/WinUI compatible) for the notification-area icon
  + flyout host.
- **Interop:** `CsWin32` (source-generated P/Invoke) for the Win32/NT APIs, or
  hand-written `windows`-targeted DllImports in a `WeChatMulti.Native` project.

Alternatives considered: Rust + `windows-rs` + Tauri/egui (more work for tray
UI, smaller ecosystem for this); C++/Win32 (most direct for handles, painful
UI); Electron/Tauri (heavy, still needs native code for the mutex). C#/.NET wins
on balance.

---

## 5. Architecture — mirror the macOS v2.0 "tested core"

Three projects, same discipline as `WeChatMultiCore` + app + tests:

```
windows/
  WeChatMulti.sln
  src/
    WeChatMulti.Core/        # pure C#, no UI, no P/Invoke — fully unit-tested
      SemVer.cs              #   (port of Core/SemVer.swift)
      InstanceOrdering.cs    #   (port of SlotOrdering)
      Settings/             #   IKeyValueStore + JSON-file store + in-memory test double
      SettingsBackup.cs      #   same JSON schema + validation as macOS
      Changelog.cs
      MutexNameRegistry.cs   #   known WeChat mutex names + match heuristic (TESTABLE)
      IHandleScanner.cs      #   interface over native enumeration (so logic is testable)
      InstanceModel.cs       #   process → instance mapping, naming/colors
    WeChatMulti.Native/      # P/Invoke wrappers (NtQuerySystemInformation, DuplicateHandle…)
      HandleScanner.cs       #   implements IHandleScanner via NT APIs
      WeChatLocator.cs       #   registry-based install detection
      LaunchAtLogin.cs       #   HKCU\…\Run
    WeChatMulti.App/         # WPF tray app (UI + orchestration), composes Core + Native
  tests/
    WeChatMulti.Core.Tests/  # xUnit — gated in CI, mirrors the 61 Swift tests
```

The **selection logic stays in Core behind interfaces** (`IHandleScanner`,
`IMutexCloser`) so the risky native bits are injected and the matching/dedup/
ordering logic is unit-tested with fakes — exactly how the macOS `ProcessTable`
parser is tested without spawning `ps`.

---

## 6. UI mapping (macOS → Windows)

| macOS | Windows |
|---|---|
| Menu bar status item (Stack glyph) | System tray (notification area) icon, jade badge when running |
| `NSPopover` flyout | Borderless WPF flyout anchored above the tray icon |
| Account rows w/ colored dots | Instance rows w/ colored dots (by launch order / detected `wxid`) |
| Preferences / About / Onboarding / What's New windows | WPF windows, jade brand + Fluent/Mica |
| First-clone progress HUD | "Preparing instance" flyout/toast |
| `UNUserNotification` banners | Windows toast (`CommunityToolkit.WinUI.Notifications`) |
| Launch at login (`SMAppService`) | `HKCU\…\CurrentVersion\Run` registry value |
| Right-click row context menu | Same, native WPF context menu |

Brand carries over verbatim: jade `#1FC56B → #07A050`, red accent `#FA3E3E`,
the Stack icon (re-exported as `.ico` + tray PNGs).

---

## 7. Data-model difference (important)

macOS has durable **numbered slots** = cloned bundles on disk. Windows
instances are **ephemeral processes** with no persistent artifact. Identity
options:

- **(v1) Launch-ordered instances** — "Instance 1, 2, …" by start order;
  names/colors assigned per order, **not durable across full restarts**. Honest
  and simple.
- **(later) Bind to `wxid`** — detect the logged-in account (e.g. by watching
  the `xwechat_files` / `WeChat Files` per-account folders for the active one)
  to give durable, account-stable identity. Fragile; investigate separately.

This is a genuine UX divergence to call out to users in onboarding.

---

## 8. Distribution

- **Code signing:** Authenticode. Unsigned → SmartScreen "Windows protected
  your PC" (the Gatekeeper analog). Plan: ship unsigned first with documented
  bypass, then **Azure Trusted Signing** (~cheap, ~$10/mo, CI-friendly) to build
  reputation. EV cert optional later.
- **Packaging:** **portable self-contained `.exe`** + an **Inno Setup** (or WiX)
  installer. **Avoid MSIX** — its container can block cross-process handle
  duplication against a normally-installed WeChat, which is the whole point.
- **Auto-update:** **Velopack** (modern Squirrel successor for .NET) — the
  Sparkle analog. Generates delta updates + an update feed from CI.
- **winget:** submit a manifest to `microsoft/winget-pkgs` (the Homebrew-cask
  analog) once signed.

---

## 9. CI (GitHub Actions, `windows-latest`)

Mirror the macOS workflows:

- `windows-build.yml` — `dotnet test` (gate) → `dotnet publish -r win-x64
  --self-contained` (+ `win-arm64`) → Inno Setup → upload artifact. Runs on
  push/PR.
- `windows-release.yml` — on a `win-v*` tag: test-gate → publish → sign →
  Velopack pack → draft GitHub release with the installer + portable zip +
  SHA256.

A failing `dotnet test` blocks the release, same contract as macOS.

---

## 10. Testing strategy (incl. the scary native bits)

- **Core (xUnit, deterministic):** SemVer, instance ordering, settings
  round-trip, backup schema + validation, **mutex-name matching** (known list +
  heuristic against fixture handle names), instance-model mapping with a fake
  `IHandleScanner`. This is the bulk and runs on every push.
- **Native integration (Windows runner):** validate `DuplicateHandle(…,
  DUPLICATE_CLOSE_SOURCE)` end-to-end against a **self-created named mutex in a
  child test process** — no WeChat required. Proves the close mechanism works on
  CI hardware.
- **Manual smoke (real WeChat):** a documented checklist per WeChat version,
  since the mutex name is the one thing CI can't verify.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Mutex name drifts across WeChat versions** (incl. 3.x vs 4.x "Weixin") | Maintained known-names list shipped in Core + a heuristic (contains "WeChat"/"Weixin" + "Mutex"/"Instance") + a "report your version" link; covered by Core tests |
| WeChat 4.x renames process to `Weixin.exe` and data dir to `xwechat_files` | Detect both 3.x and 4.x process/data conventions; locator reads the registry install path |
| UAC/admin needed for handle duplication | Try `asInvoker` first; only prompt for elevation on access-denied; document |
| **AV / EDR false positives** (Duplicate-close looks malware-ish) | Code signing + reputation; clear open-source provenance; avoid bundling Sysinternals |
| WeChat changes the singleton mechanism entirely | Same risk class as macOS clone trick; isolate behind `IMutexCloser` so a new strategy is a drop-in |
| MSIX sandbox blocks the mechanism | Don't ship MSIX; use installer/portable exe |

---

## 12. Phased roadmap

- **Phase 0 — Spike (1–2 days):** prove the mechanism on a real machine
  (prototype may shell to `handle64.exe`), confirm current mutex/process names
  for installed WeChat 3.x **and** 4.x. Go/no-go gate.
- **Phase 1 — MVP:** tray icon + "Launch new instance" (native in-process
  mutex-close + spawn) + running-instance count + quit. Self-contained exe.
- **Phase 2 — Core + tests + CI:** extract `WeChatMulti.Core`, xUnit suite,
  `windows-build.yml` test gate. (Matches macOS v2.0 discipline.)
- **Phase 3 — Parity UI:** flyout with instance rows, naming + colors,
  Preferences, About, Onboarding, What's New, toasts, launch-at-login.
- **Phase 4 — Distribution:** Azure Trusted Signing, Inno Setup installer,
  Velopack auto-update, winget manifest, `windows-release.yml`.
- **Phase 5 — Durable identity (R&D):** `wxid`-bound instances if feasible.

---

## 13. Repo structure

Keep one repo. Add a top-level `windows/` solution alongside the existing macOS
sources; share `docs/`, brand assets, `CHANGELOG`, and the backup JSON schema.
Tag releases per platform: `v*` (macOS, existing) and `win-v*` (Windows), or
move to unified `v*` with per-platform release assets. Cross-link both READMEs.

Proposed layout:

```
/                      # macOS app (unchanged) + shared docs/assets
/windows/              # .NET solution (this plan)
/docs/windows-port-plan.md
```

---

## 14. Open questions for the user

1. **Scope of v1** — MVP (tray + launch + count + quit) first, or hold for full
   UI parity before any release?
2. **Repo** — same repo with `windows/`, or a separate `wechat-multi-windows`?
3. **Signing budget** — OK to set up Azure Trusted Signing (~$10/mo) for a clean
   SmartScreen experience, or ship unsigned with a documented bypass initially?
4. **Min Windows version** — Windows 11 only (Mica/Fluent, simpler) or also
   Windows 10 (larger audience, plainer theming)?
5. **WeChat version target** — confirm whether your users run WeChat **3.x**
   (`WeChat.exe`) or the newer **4.x / Weixin** (`Weixin.exe`); it determines the
   mutex/process/data conventions we hard-code first.
   → **Decided: target both defensively** with runtime detection (see Appendix A).

---

# Appendices (engineering detail)

> Anything marked **⚠ verify in Phase 0** is a value that must be confirmed
> against a live install before it's trusted in code. Both WeChat 3.x and the
> 4.x "Weixin" line are targeted; the app detects which is present at runtime.

## Appendix A — WeChat version matrix (3.x vs 4.x)

| Aspect | WeChat 3.x | WeChat 4.x ("Weixin") |
|---|---|---|
| Main process | `WeChat.exe` | `Weixin.exe` |
| Helper procs to **exclude** | `WeChatApp.exe`, `WeChatAppEx.exe`, `WeChatBrowser.exe`, `WeChatPlayer.exe`, `WeChatWeb.exe`, `WeChatUtility.exe`, `WeChatOCR.exe` | `Weixin`-prefixed helpers + the same CEF/util helpers ⚠ verify |
| Singleton mutex name | `_WeChat_App_Instance_Identity_Mutex_Name` (widely cited) ⚠ verify on current build | **unknown — likely `Weixin`-based**, ⚠ verify in Phase 0 |
| Install path (registry) | `HKCU\Software\Tencent\WeChat` → `InstallPath` | `HKCU\Software\Tencent\Weixin` (or similar) ⚠ verify |
| Chat data root | `%USERPROFILE%\Documents\WeChat Files\` | `%USERPROFILE%\Documents\xwechat_files\` |
| Per-account partition | one subfolder per `wxid` | one subfolder per account id |

**Runtime detection (most-robust first):**

1. Find a running main process whose name ∈ {`WeChat.exe`, `Weixin.exe`} and
   whose `MainModule.FileName` is the top-level install (not a helper subpath).
   Use its module path as the exe path. *(Most robust — no registry guessing.)*
2. Else read the registry install path for whichever brand is present.
3. Else probe default locations (`%ProgramFiles%\Tencent\WeChat\WeChat.exe`,
   `…\Tencent\Weixin\Weixin.exe`).

The detected brand (`Brand.weChat3` / `Brand.weixin4`) selects the helper-
exclusion set, mutex-name candidates, and data-root — all data-driven from a
table so adding a future variant is a one-line change.

## Appendix B — Native interop (P/Invoke)

The handle scan lives in `WeChatMulti.Native`, behind the Core `IHandleScanner`
interface. Signatures (hand-written DllImport shown; `CsWin32` can generate
equivalents):

```csharp
// ntdll.dll
[DllImport("ntdll.dll")]
static extern int NtQuerySystemInformation(
    int SystemInformationClass,            // 0x40 = SystemExtendedHandleInformation
    IntPtr SystemInformation, int Length, out int ReturnLength);

[DllImport("ntdll.dll")]
static extern int NtQueryObject(
    IntPtr Handle, int ObjectInformationClass, // 1 = Name, 2 = Type
    IntPtr ObjectInformation, int Length, out int ReturnLength);

// kernel32.dll
[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr OpenProcess(uint access, bool inherit, int pid); // 0x0040 PROCESS_DUP_HANDLE

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool DuplicateHandle(
    IntPtr hSourceProcess, IntPtr hSource, IntPtr hTargetProcess,
    out IntPtr lpTarget, uint access, bool inherit, uint options); // 0x1 DUPLICATE_CLOSE_SOURCE

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool CloseHandle(IntPtr h);
```

Structures: `SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX { Object, UniqueProcessId,
HandleValue, GrantedAccess, CreatorBackTraceIndex, ObjectTypeIndex,
HandleAttributes, Reserved }` inside `SYSTEM_HANDLE_INFORMATION_EX`.

**Scan + close algorithm:**

```
1. pids = main WeChat processes (Appendix A detection)
2. Loop NtQuerySystemInformation(0x40) growing the buffer until status != 0xC0000004
3. For each entry with UniqueProcessId ∈ pids:
     skip if GrantedAccess == 0x0012019F          // known NtQueryObject hang mask
     proc = OpenProcess(PROCESS_DUP_HANDLE, pid)
     DuplicateHandle(proc, entry.HandleValue, self, out dup, 0, false, DUPLICATE_SAME_ACCESS)
     if NtQueryObject(dup, Type) != "Mutant": CloseHandle(dup); continue
     name = NtQueryObject(dup, Name)  on a worker thread w/ ~50ms timeout
     CloseHandle(dup)
     if MutexNameRegistry.matches(name, brand):  candidates += (pid, entry.HandleValue)
4. For each candidate: DuplicateHandle(proc, handleValue, self, out d, 0, false,
                                       DUPLICATE_CLOSE_SOURCE); CloseHandle(d)   // closes in target
5. If any close failed with ERROR_ACCESS_DENIED → surface "try elevated" path
6. Process.Start(exePath)
```

`IHandleScanner` returns the candidate list; `IMutexCloser` performs step 4.
Both are injected so Core logic (selection, dedup, brand matching, the elevation
decision) is unit-tested with fakes and **no WeChat or admin rights needed**.

## Appendix C — Core interfaces & MutexNameRegistry

```csharp
public interface IHandleScanner {                 // Native implements; tests fake
    IReadOnlyList<MutexHandle> FindInstanceMutexHandles(IReadOnlyList<int> weChatPids, WeChatBrand brand);
}
public interface IMutexCloser { CloseResult CloseInTarget(MutexHandle h); }
public interface IProcessLister { IReadOnlyList<WeChatProcess> RunningMainProcesses(); }
public interface IProcessLauncher { void Launch(string exePath); }

public static class MutexNameRegistry {
    // Exact, version-pinned names take priority…
    static readonly Dictionary<WeChatBrand, string[]> Known = new() {
        [WeChatBrand.WeChat3] = new[] { "_WeChat_App_Instance_Identity_Mutex_Name" }, // ⚠ verify
        [WeChatBrand.Weixin4] = new string[] { /* ⚠ fill in Phase 0 */ },
    };
    // …then a heuristic fallback so an unseen version still has a chance.
    public static bool Matches(string handleName, WeChatBrand brand) {
        if (Known[brand].Any(k => handleName.Equals(k, OrdinalIgnoreCase))) return true;
        var n = handleName.ToLowerInvariant();
        return (n.Contains("wechat") || n.Contains("weixin"))
            && (n.Contains("instance") || n.Contains("mutex"));
    }
}
```

This is the Windows analog of the macOS "clone trick may need revisiting" — the
maintenance surface is concentrated here and **fully unit-tested**.

## Appendix D — Core test list (mirrors the 61-test macOS suite)

- **SemVerTests** — ordering, zero-padding, lenient suffix parse (port verbatim).
- **InstanceOrderingTests** — reorder/resolve (port of SlotOrdering).
- **SettingsTests** — JSON-file store round-trip + in-memory double semantics.
- **SettingsBackupTests** — same schema + validation + stale-path drop (port).
- **ChangelogTests** — newest-first, `EntriesNewer`.
- **MutexNameRegistryTests** — known names match per brand; heuristic matches
  `wechat/weixin + instance/mutex`; rejects unrelated mutants; case-insensitive.
- **InstanceSelectionTests** — given a fake `IHandleScanner` returning a mix of
  WeChat mutants, helpers, and noise → correct candidate set, dedup across PIDs,
  empty when none running.
- **BrandDetectionTests** — process/exe/data mapping for 3.x vs 4.x from fakes.
- **Native integration (Windows runner only):** create a named mutex in a child
  process, prove `DUPLICATE_CLOSE_SOURCE` destroys it and a re-create succeeds —
  validates the real mechanism without WeChat.

## Appendix E — CI workflows (sketch)

```yaml
# .github/workflows/windows-build.yml
name: windows-build
on: { push: { branches: [main] }, pull_request: { branches: [main] } }
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0.x' }
      - run: dotnet test windows/WeChatMulti.sln -c Release        # gate
      - run: dotnet publish windows/src/WeChatMulti.App -c Release -r win-x64 --self-contained
      - run: dotnet publish windows/src/WeChatMulti.App -c Release -r win-arm64 --self-contained
```

```yaml
# .github/workflows/windows-release.yml  (on tag win-v*.*.*)
#   dotnet test (gate) → publish x64+arm64 → sign (Azure Trusted Signing)
#   → Velopack pack → gh release create with installer + portable zip + SHA256
```

A failing `dotnet test` blocks the release — same contract as the macOS
workflows.

## Appendix F — Phase 0 discovery recipe (do this first)

On a real machine with WeChat installed and running, confirm the unknowns:

1. **Process + exe path:** `Get-Process WeChat,Weixin | Select Name,Path` →
   record the main exe name and install path; confirm helper names to exclude.
2. **Mutex name:** Process Explorer → *Find → Find Handle or DLL* → search
   `WeChat` / `Weixin`; note every **Mutant** name. Or
   `handle64.exe -a -p WeChat.exe` (prototype only — not redistributable).
3. **Validate the close manually:** with `handle64.exe -c <hex> -p <pid> -y` on
   that mutant, then double-click WeChat → a second window should appear.
4. **Privilege check:** does the close work as a normal user, or only elevated?
   Record — it decides the app manifest.
5. **Repeat for both 3.x and 4.x.** Fill the ⚠ values in Appendices A & C.

Outcome of Phase 0 = a go/no-go and the concrete constants to ship. Everything
downstream (Core registry, tests, UI) is already designed around these slots.

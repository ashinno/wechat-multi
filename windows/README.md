# WeChat Multi — Windows

A Windows tray utility to run multiple WeChat instances at once. Sibling to the
macOS app at the repo root; see [`docs/windows-port-plan.md`](../docs/windows-port-plan.md)
for the full design.

> **Status: in development (Phase 1–2).** The tested Core and native interop are
> done; the tray app is a working skeleton. The concrete WeChat mutex/process
> names still need Phase-0 verification on a real install (see the plan).

## How it works (vs. macOS)

macOS clones the `.app` bundle to get a fresh sandbox per instance. Windows has
no equivalent and doesn't need one: WeChat's single-instance lock is a **named
kernel mutex**, and all instances already share one install with per-account
(`wxid`) data. So the engine is:

> find WeChat's processes → close their handle to the instance mutex in **all**
> of them → launch another `WeChat.exe`.

## Solution layout

```
windows/
  WeChatMulti.sln
  src/
    WeChatMulti.Core/      net8.0   — pure logic, 68 unit tests, no Windows APIs
    WeChatMulti.Native/    net8.0-windows — P/Invoke: handle scan, mutex close, locator, login
    WeChatMulti.App/       net8.0-windows — WPF tray app (H.NotifyIcon)
  tests/
    WeChatMulti.Core.Tests/ net8.0  — xUnit, gated in CI
```

`WeChatMulti.Core` is the Windows analog of the macOS `WeChatMultiCore`: all the
bug-prone logic (version compare, ordering, settings, backup, the **mutex-name
registry**, and the launch orchestration) lives behind interfaces
(`IHandleScanner`, `IMutexCloser`, `IProcessLister`, `IProcessLauncher`) and is
fully unit-tested — so the risky native bits are injected and the decisions are
verified with fakes, no WeChat or admin rights required.

## Build & test

On Windows:

```powershell
cd windows
dotnet test  tests/WeChatMulti.Core.Tests              # the gate (68 tests)
dotnet build src/WeChatMulti.App                       # builds Core + Native + App
dotnet run  --project src/WeChatMulti.App
```

On macOS/Linux you can build everything (handy for CI parity) by enabling the
Windows targeting pack:

```bash
cd windows
dotnet test  tests/WeChatMulti.Core.Tests                          # Core is cross-platform
dotnet build src/WeChatMulti.App -p:EnableWindowsTargeting=true     # compiles the WPF app too
```

> The solution file is `WeChatMulti.slnx` (the modern XML format; needs .NET SDK
> 9.0.200+). Building by csproj path as above works on any .NET 8+ SDK, which is
> what CI does.

CI (`.github/workflows/windows-build.yml`) runs the test gate, builds the app
(which pulls in Core + Native), and publishes self-contained x64 + arm64 on
`windows-latest`.

## Roadmap

See the [port plan](../docs/windows-port-plan.md). Next up: **Phase 0** — confirm
the WeChat 3.x and 4.x mutex/process names on real installs and fill the
`VERIFY` slots in `MutexNameRegistry` / `BrandConventions`.

## Caveats

- The instance-mutex name is **version-dependent** and may change across WeChat
  releases — the maintenance surface is concentrated in `MutexNameRegistry`.
- Closing the mutex may require running elevated depending on WeChat's integrity
  level; the app detects access-denied and offers to relaunch as admin.
- Cross-process handle duplication can trip antivirus heuristics — code signing
  + open-source provenance mitigate this.
- Unaffiliated with Tencent. WeChat/Weixin are trademarks of Tencent.

<p align="center">
  <img src="docs/icon.png" width="180" alt="WeChat Multi icon" />
</p>

# WeChat Multi

> Run multiple WeChat accounts side by side on macOS — from a single menu bar icon.

**English** | [简体中文](README.zh-CN.md)

![platform](https://img.shields.io/badge/platform-macOS%2012%2B-blue)
![swift](https://img.shields.io/badge/swift-5.7%2B-orange)
![license](https://img.shields.io/badge/license-MIT-green)

WeChat for Mac enforces a singleton: it only lets you launch one copy at a
time and silently kills any second process. **WeChat Multi** gets around that
by cloning `/Applications/WeChat.app` into uniquely-identified copies under
`~/Applications/WeChat Multi/`. Each clone has its own `CFBundleIdentifier`,
so macOS gives it a fresh sandbox container and WeChat treats it as a separate
app with its own login session.

The result: you can sign in to as many accounts as you want — work and
personal, two phone numbers, a burner — each in its own window, each
surviving restarts.

## What the menu looks like

```
 💬 WC 2                                          ⏰ 9:41
 ┌──────────────────────────────────────┐
 │ 2 WeChat instances running           │
 ├──────────────────────────────────────┤
 │ ⚠️ 1 clone out of date               │
 │ Refresh Outdated Clones…             │
 ├──────────────────────────────────────┤
 │ Launch New Instance              ⌘N  │
 ├──────────────────────────────────────┤
 │ Running                              │
 │ Main account — PID 34810           › │
 │ Work (Slot 1) — PID 40853          › │
 │ Quit All Instances               ⌘K  │
 ├──────────────────────────────────────┤
 │ Choose WeChat.app Location…          │
 │   ↳ /Applications/WeChat.app         │
 │ Open Clones Folder                   │
 │ Reset All Clones (1)…                │
 ├──────────────────────────────────────┤
 │ About WeChat Multi                   │
 │ Quit WeChat Multi                ⌘Q  │
 └──────────────────────────────────────┘
```

Each running-instance row expands to a submenu with **Bring to Front**,
**Quit This Instance**, and **Rename…** (lets you name a clone "Work" or
"Personal" — the name shows in Cmd+Tab and the Dock).

The **⚠️ outdated clones** row only appears when WeChat has updated since
your clones were last built; one click rebuilds them while preserving each
clone's signed-in session.

## Download

Don't want to compile? Grab the pre-built `.app` from
[the latest release](https://github.com/ashinno/wechat-multi/releases/latest),
drag it into `/Applications`, and double-click. macOS may ask you to right-
click → Open the first time because it's ad-hoc signed.

## Features

- 🍎 **Native menu bar app** — no Dock clutter, no Electron, ~190 KB binary
- ⚡ **One click to launch** a new, isolated WeChat instance
- 🏷️ **Per-slot custom names** ("Work", "Personal") — shown in Cmd+Tab and Dock
- 🔄 **Auto-detects WeChat updates** and offers to refresh stale clones,
  preserving each clone's signed-in session
- 📋 **Lists running instances** with their PIDs and start times
- 🪟 **Bring any instance to the front**, quit individual instances, or quit all
- 🔍 **Auto-detects WeChat** in `/Applications`; falls back to a file picker
- 🖥️ **Apple Silicon native**, ad-hoc signed, no third-party dependencies

## Requirements

- macOS 12 Monterey or later
- The official WeChat app installed at `/Applications/WeChat.app`
- Xcode Command Line Tools (`xcode-select --install`) — only needed to build

## Install

```bash
git clone https://github.com/ashinno/wechat-multi.git
cd wechat-multi
./install.sh
```

`install.sh` runs `build.sh` if needed, copies the bundle to
`/Applications/WeChat Multi.app`, and launches it. The first launch shows a
brief alert pointing at the menu bar; look for **WC** in the top-right corner
of your screen.

To build without installing:

```bash
./build.sh
open "dist/WeChat Multi.app"
```

## Usage

1. Click the **WC** icon in the menu bar
2. Choose **Launch New Instance** (⌘N)
   - The first time each slot is created the app spends a few seconds
     cloning WeChat.app (APFS makes this near-instant once the file system
     primes)
   - A separate WeChat window appears, ready for a fresh login
3. Repeat as many times as you need accounts. Slot numbers go up indefinitely
4. Each running instance shows up in the menu. Hover one to:
   - **Bring to Front** — focuses that specific WeChat window
   - **Quit This Instance** — sends SIGTERM to just that PID
   - **Rename…** — name a clone "Work", "Personal", etc.; Cmd+Tab and the
     Dock pick up the new name the next time you launch it
5. **Quit All Instances** terminates every WeChat (clones and the original)

The original `/Applications/WeChat.app` is left untouched. You can keep
launching it normally from the Dock or Spotlight; it shows up in the menu as
"Main account".

### After a WeChat update

When the official WeChat updates itself, your clones are still on the old
version. The app detects this automatically the next time you open the menu
and shows **⚠️ N clones out of date**; click **Refresh Outdated Clones…** to
rebuild them from the new `/Applications/WeChat.app`.

Per-account sandbox containers (saved logins, chat history) are preserved
during refresh because they live in `~/Library/Containers/com.wechatmulti.cloneN/`,
which is separate from the bundle being replaced. Custom slot names are
preserved too. You will need to quit running instances that are being
refreshed; the dialog asks for confirmation first.

If you want a *full* reset including sandbox data:

```bash
# Quit everything first via the menu, then:
rm -rf "$HOME/Applications/WeChat Multi"
rm -rf "$HOME/Library/Containers/com.wechatmulti.clone"*
```

## How it works

For each slot *N*, the app:

1. `cp -Rc /Applications/WeChat.app ~/Applications/WeChat Multi/WeChat N.app`
   (the `-c` flag uses APFS copy-on-write, so it's instant and uses no extra
   disk space until WeChat writes to the bundle)
2. Rewrites `Contents/Info.plist`:
   - `CFBundleIdentifier` → `com.wechatmulti.cloneN`
   - `CFBundleName` / `CFBundleDisplayName` → your custom slot name, or
     `WeChat N` as a fallback
3. Deletes `Contents/_CodeSignature` (modifying Info.plist invalidates the
   original Tencent signature)
4. `codesign --force --deep --sign - <clone>` (ad-hoc re-sign)
5. `xattr -dr com.apple.quarantine <clone>` (skip the Gatekeeper first-launch
   prompt)
6. `open -na <clone>`

Because each clone has a different bundle identifier, macOS allocates a
separate sandbox container and WeChat's "another instance is running" check
doesn't fire.

The trade-off of ad-hoc signing: keychain access entitlements tied to
Tencent's team ID no longer apply, so passwords aren't shared between clones.
You'll log in fresh per instance — which is exactly what you want for
multi-account use.

## Uninstall

```bash
# Quit the menu bar app, then:
rm -rf "/Applications/WeChat Multi.app"
rm -rf "$HOME/Applications/WeChat Multi"
rm -rf "$HOME/Library/Containers/com.wechatmulti.clone"*
defaults delete com.wechatmulti.app 2>/dev/null
```

## Caveats

- WeChat's auto-update only runs inside `/Applications/WeChat.app`. Clones
  are read-only as far as Sparkle is concerned — rebuild them via **Reset
  All Clones** after the official app updates
- macOS treats each clone as a distinct app for permissions. The first time
  a clone wants camera, microphone, or screen-recording access, you'll get
  the standard prompt and need to grant it
- Notifications are namespaced per bundle ID, so each instance gets its own
  banner style and "Do Not Disturb" entry in System Settings
- This tool is unofficial and not affiliated with Tencent. Use at your own
  risk; if WeChat changes how it enforces single-instance behavior in a
  future update, the clone trick may need to be revisited

## Project layout

```
.
├── Package.swift                 # Swift Package Manager manifest
├── Sources/WeChatMulti/
│   ├── main.swift                # NSApplication entry point
│   ├── AppDelegate.swift         # Menu bar UI
│   └── WeChatLauncher.swift      # Clone management + ps inspection
├── Resources/Info.plist          # Bundle metadata (LSUIElement = true)
├── build.sh                      # swift build → .app bundle assembly
└── install.sh                    # Copy to /Applications and launch
```

## Contributing

PRs welcome. A few directions if you're looking for ideas:

- Universal binary build (currently arm64 only)
- "Launch at login" toggle via `SMAppService`
- A proper `.icns` icon and About panel artwork
- Notification when a clone finishes preparing for the first time
- Homebrew cask

## License

[MIT](LICENSE) © 2026 ashinno

WeChat is a trademark of Tencent Holdings Ltd. This project is not
affiliated with, endorsed by, or sponsored by Tencent.

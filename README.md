# Awake

**English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

A macOS menu bar app that keeps your Mac awake while AI coding agents are running — even with the lid closed.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Agent-driven keep awake** — follows Codex, Claude Code, OpenCode, and Antigravity through their own hook events. No process polling.
- **Other keep-awake modes** — for a fixed duration (15m–3h), while a download is in progress, or indefinitely.
- **Cooling** — optional fan control while an agent is running with the lid closed (Apple Silicon). Native clamshell operation leaves fans to macOS.
- **Battery protection** — turns everything off and restores automatic fan control at a configurable battery level (Off, 5–25%, default 20%). Automatic starts stay paused below that level, but you can still start Awake manually.
- **Display control** — optionally prevents display sleep, the screen saver, and automatic idle lock during a session.
- **Closed-lid Low Power Mode** — optionally turns on macOS Low Power Mode while the lid is closed during a session, and restores your previous setting afterwards.
- **Notifications** — tells you when Awake stops automatically or a protection mechanism fails.
- **In-app updates** — checks GitHub Releases and installs new versions inside the app (Sparkle, EdDSA-verified); no account required.

## Requirements

- macOS 26 (Tahoe) or later. macOS 27 (Golden Gate) is supported; macOS 27 itself runs only on Apple silicon.
- Apple Silicon Mac recommended: closed-lid fan control is built for Apple Silicon. The other features also work on Intel Macs running macOS 26.
- The app UI is available in English and Japanese.

## Installation

1. Download `Awake-x.y.z.zip` from the [latest release](https://github.com/PMGWork/awake/releases/latest). Each release also includes `Awake-x.y.z.dmg`, which opens as a drag-to-Applications window.
2. Unzip it and move `Awake.app` to `/Applications`.
3. Builds are not notarized (no paid Apple Developer account), so the first launch needs one Gatekeeper step:
   - Try to open `Awake.app` once and dismiss the warning, then go to **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway**, or
   - Clear the quarantine attribute: `xattr -r -d com.apple.quarantine /Applications/Awake.app`
   - With the DMG, macOS asks for the same approval of the disk image when you open it (that dialog has no *Open* button; use **System Settings → Privacy & Security**), then for the app after copying it to `/Applications`.

Awake runs only in the menu bar (no Dock icon).

## Usage

- **Left-click** the menu bar cup to open the menu. **Right-click** to toggle the current mode's primary action.
- Modes:
  - *While Agent Is Running* — keeps the Mac awake while a linked agent has an active session.
  - *For Duration* — countdown timer (15m / 30m / 1h / 2h / 3h), remembered across launches.
  - *While Downloading* — watches a folder (default `~/Downloads`) for unfinished downloads.
  - *Indefinitely* — until you stop it.
- Settings:
  - **General** — language (system default, English, or Japanese), launch at login, notifications, remaining time in the menu bar, and updates.
  - **Keep Awake** — display and screen saver, closed-lid operation, Low Power Mode with the lid closed, and battery cutoff.
  - **Monitor** — link or unlink each agent provider, watch live sessions, and choose the download folder.
  - **Cooling** — separate automatic and manual fan speeds, and options for the agent mode.
  - **Permissions** — install, update, or remove the shared helper.

## Agent integrations

Awake links a provider by adding the bundled `AwakeHookBridge` command (installed at `~/Library/Application Support/Awake/bin`) to that provider's own configuration:

| Provider | Configuration file |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| OpenCode | `~/.config/opencode/opencode.json` (or `opencode.jsonc`), plus a plugin in `~/Library/Application Support/Awake/integrations/opencode` |
| Antigravity | `~/.gemini/config/hooks.json` |

- Only entries owned by Awake (marked with `--owner pmgwork.awake`) are added or removed.
- Before the first change, the original file is backed up next to it as `<file>.awake-backup`.
- **Unlink** in Settings → Agents removes only Awake's entries.
- Session events are stored as JSON files under `~/Library/Application Support/Awake/agent-sessions/v1` (permissions 0700). The latest event per session is retained after completion to reject delayed older events, and is replaced when a new turn starts.

## Cooling

Cooling is separate from Keep Awake. Pick a **Cooling Mode** in the menu, then press **Start Cooling**. Settings → Cooling has separate fan speeds for **Automatic Cooling** (While Agent Is Running) and **Manual Cooling** (Indefinitely and For Duration), both defaulting to 100% on new installations. Existing fan-speed settings are carried over to both. While cooling is stopped or paused, macOS controls the fans.

| Mode | Behavior |
|---|---|
| Indefinitely | Fans stay up until you stop cooling |
| For Duration | 5 / 10 / 15 / 30 minutes, then fans go back to macOS |
| While Agent Is Running | While a monitored agent is running with the lid closed. Starts when selected; pause or resume it from the menu (default) |

- Check authorization and install or update the shared privileged helper under Settings → Permissions. Closed-lid operation and fan control use the same helper.
- The first activation asks for an administrator password once to install a small privileged helper at `/Library/PrivilegedHelperTools/pmgwork.awake.smc` (`root:admin`, setuid root).
- The helper holds a fan lease and watches the Awake process, so automatic fan control is restored if Awake exits or crashes.
- Cooling stops when the battery reaches the low-battery cutoff. Indefinite and timed cooling are not kept after a relaunch.
- "While Agent Is Running" option: "Only When Plugged In". Agent cooling runs only with the lid closed.
- With the lid closed and an external display connected, all cooling modes leave fan control to macOS. Awake does not override closed-lid sleep or enable Low Power Mode in this state. Cooling resumes when this state ends if the selected mode still applies.
- Use Remove… in Settings → Permissions to remove the helper. Awake stops the current session, restores automatic fan control, removes the shared helper, and turns off closed-lid operation and cooling.

## Privacy

- Agent activity is detected from local hook events under `~/Library/Application Support/Awake`. Awake does not poll running processes and does not inspect your project or document files.
- Download detection only looks at file names (`.download`, `.crdownload`, `.part`, …, skipping hidden files) in the folder you choose.
- No analytics, no telemetry, no account. Awake contacts GitHub only to read `releases/latest` for update checks and to download an update after you agree to install it. Anonymous system profiling is disabled.

## Building from source

Requires Xcode 16 or later. Release builds are made with Xcode 27 and the macOS 27 SDK, so the app adopts the macOS 26/27 appearance and behavior changes. The only third-party dependency is [Sparkle](https://sparkle-project.org) for in-app updates, resolved with Swift Package Manager.

```sh
git clone https://github.com/PMGWork/awake.git
cd awake
open awake.xcodeproj
```

Or build from the command line:

```sh
xcodebuild -project awake.xcodeproj -scheme awake -configuration Debug build
```

Run the unit tests from Xcode with **Product ▸ Test** (target `awakeTests`). The app target uses a file-system synchronized group, so new files under `awake/` are picked up automatically.

Release (distribution) steps are documented in `docs/DISTRIBUTION.md`.

## Project layout

| Path | Contents |
| --- | --- |
| `awake/` | App sources (Models, Services, State, Views, localized strings) |
| `AwakeHookBridge/` | Command line tool that agent hooks invoke |
| `awakeTests/` | Unit tests |
| `docs/` | Distribution notes and design documents |
| `scripts/` | Packaging and data-reset helpers |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| macOS blocks the first launch | System Settings → Privacy & Security → **Open Anyway**, or clear the quarantine attribute (see Installation) |
| In-app updates fail | Replace the app with the latest release from GitHub |
| Fan control is unavailable | Settings → Permissions → **Install** / **Update** |
| Agents are not detected | Settings → Agents → **Link** for that provider, then **Test** |

## License

MIT License. See [LICENSE](LICENSE).

Copyright (c) 2026 PMGWork

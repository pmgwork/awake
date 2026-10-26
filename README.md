# Awake

**English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

A macOS menu bar app that keeps your Mac awake while AI coding agents are running — even with the lid closed.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Agent-driven keep awake** — follows Codex, Claude Code, OpenCode, and Antigravity through their own hook events. No process polling.
- **Other keep-awake modes** — for a fixed duration (15m–3h), while a download is in progress, or indefinitely.
- **Cooling** — optional fan control while an agent is running with the lid closed, plus manual cooling in any display setup (Apple Silicon). With an external display connected and the lid closed, automatic cooling leaves fans to macOS.
- **Battery protection** — turns Keep Awake and agent cooling off and restores automatic fan control at a configurable battery level (Off, 5–25%, default 20%). Automatic starts stay paused below that level, but you can still start Awake manually.
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

Beta releases are marked **Pre-release** on the [releases page](https://github.com/PMGWork/awake/releases) (for example, `v0.6.0-beta.1`). Enable **Settings → General → Receive Beta Updates** to include them in in-app update checks. This is off by default. The beta feed includes stable releases too, so you can update to the matching stable version when it is released. Turning the setting off stops future beta updates and does not downgrade your installed version. You can also install a beta manually using the steps above.

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

## Command line

The app bundles an `awake` command. After moving Awake.app to `/Applications`, add it to your PATH once:

```sh
mkdir -p "$HOME/.local/bin"
ln -s /Applications/Awake.app/Contents/Helpers/awake "$HOME/.local/bin/awake"
```

Ensure `~/.local/bin` is on your PATH. If that command name already exists, choose another location instead of replacing it. The symlink continues to work after app updates at the same location. Remove the symlink to uninstall the command.

```sh
awake start                 # Start indefinitely
awake start --duration 30m  # Start for 30 minutes
awake stop                  # Stop Keep Awake
awake status                # Show state, mode, remaining seconds, and sleep-prevention health
awake status --json         # Machine-readable status (ISO 8601 timer end date)
awake --help
```

The command launches its containing app in the background if needed and controls the same session shown in the menu bar. `start` selects Indefinitely; `start --duration` selects For Duration and saves the duration. Repeating `start` replaces the current session and resets its timer. Durations accept positive whole numbers followed by `s`, `m`, or `h`, up to 7 days. `stop` stops Keep Awake; cooling remains independent. CLI starts follow the same rules as manual starts, including the low-battery override. Existing hardware permissions still apply. Status includes the actual sleep-prevention health; an active session can report degraded or failed protection. Commands return 0 on success and nonzero on invalid input, connection failure, or a rejected command. The CLI requires the app and a logged-in macOS GUI session.

Actions print a one-line result. Input errors stay brief; `awake --help` shows the full help. Use `status` for details or `status --json` for scripts.

Mode selection and cooling are also available:

```sh
awake mode agent
awake start --mode download
awake mode timer --duration 1h
awake start --mode timer
awake cooling start --mode indefinitely
awake cooling start --duration 10m
awake cooling mode agent
awake cooling speed automatic 75
awake cooling speed manual 50
awake cooling stop
awake cooling status --json
```

Keep Awake modes are `indefinitely`, `timer`, `agent`, and `download`; cooling supports `indefinitely`, `timer`, and `agent`. `awake mode` and `awake cooling mode` without a value show the current state. Selecting a mode follows the menu: changing it stops the previous session; manual modes wait for Start, and selecting agent cooling arms it when available. `awake start --mode timer` uses the saved duration; `awake start --mode agent` or `download` requires that monitor to be enabled and waits for activity when idle. `awake cooling start` uses the selected cooling mode. A duration implies `timer`; combining a duration with a different mode is rejected.

Cooling durations match the app presets: `5m`, `10m`, `15m`, or `30m`. Automatic and manual speeds accept `50`, `75`, or `100` percent. Starting cooling or changing its speed requires the installed helper; CLI commands do not install it or request authorization. Battery protection, the lid state, and external-display rules still apply. A rejected start leaves the selected mode and timer unchanged. `status` includes nested `cooling` state: `armed` means started, `active` means policy currently requests cooling, and `fanControl` reports the controller's applied mode (`auto` or a percentage), not a measured RPM. Fan commands are asynchronous; inspect `status` again to see the result and any error. Keep Awake's `waitingForActivity` indicates a selected conditional mode with monitoring enabled. Cooling commands leave Keep Awake independent.

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
- Monitoring uses filesystem change notifications and cached session snapshots to keep idle CPU usage low. Disabled monitors stop watching; agent monitoring remains active when needed for automatic cooling.
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
- Agent cooling stops when the battery reaches the low-battery cutoff, with a notification, and can't be resumed until the battery recovers or the Mac is plugged in. Indefinite and timed cooling keep running because you started them yourself. Indefinite and timed cooling are not kept after a relaunch.
- "While Agent Is Running" option: "Only When Plugged In". Agent cooling runs only with the lid closed.
- With the lid closed and an external display connected, automatic agent cooling leaves fan control to macOS; manual cooling keeps running. Awake does not override closed-lid sleep or enable Low Power Mode in this state. Automatic cooling resumes when this state ends if an agent is still running.
- Use Remove… in Settings → Permissions to remove the helper. Awake stops the current session, restores automatic fan control, removes the shared helper, and turns off closed-lid operation and cooling.

## Privacy

- Agent activity is detected from local hook events under `~/Library/Application Support/Awake`. Awake does not poll running processes and does not inspect your project or document files.
- Download detection only looks at file names (`.download`, `.crdownload`, `.part`, …, skipping hidden files) and modification dates in the folder you choose. In subfolders, such files count only if they changed in the last 10 minutes, so leftovers in extracted archives don't keep your Mac awake.
- No analytics, no telemetry, no account. Awake reads update feeds hosted on `raw.githubusercontent.com` and downloads updates from GitHub Releases after you agree to install them. Anonymous system profiling is disabled.

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

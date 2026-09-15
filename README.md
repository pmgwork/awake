# Awake

**English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

A macOS menu bar app that keeps your Mac awake while AI coding agents are running — even with the lid closed.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Agent-driven keep awake** — follows Codex, Claude Code, OpenCode, and Antigravity through their own hook events. No process polling.
- **Other keep-awake modes** — for a fixed duration (15m–3h), while a download is in progress, or indefinitely.
- **Completion grace period** — stays awake for another 1–5 minutes after the last agent or download finishes.
- **Closed-lid cooling** — optional fan control while the lid is closed and no external display is attached (Apple Silicon).
- **Battery protection** — turns everything off and restores automatic fan control at a configurable battery level (Off, 5–25%, default 20%).
- **Display control** — optionally prevents display sleep, the screen saver, and automatic idle lock during a session.
- **Global shortcut** — run the menu bar's main action from any app with a key combination you record.
- **Notifications** — tells you when Awake stops automatically or a protection mechanism fails.
- **Update check** — reads GitHub Releases; no account required.

## Requirements

- macOS 13 (Ventura) or later. macOS 27 (Golden Gate) is supported; macOS 27 itself runs only on Apple silicon.
- Apple Silicon Mac recommended: closed-lid fan control is built for Apple Silicon. The other features also work on Intel Macs running macOS 13–26.
- The app UI is available in English and Japanese.

## Installation

1. Download `Awake-x.y.z.zip` from the [latest release](https://github.com/PMGWork/awake/releases/latest).
2. Unzip it and move `Awake.app` to `/Applications`.
3. Builds are not notarized (no paid Apple Developer account), so the first launch needs one Gatekeeper step:
   - On macOS 15 or later (including 26/27): try to open `Awake.app` once and dismiss the warning, then go to **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway**, or
   - Clear the quarantine attribute: `xattr -r -d com.apple.quarantine /Applications/Awake.app`
   - On macOS 14 or earlier, right-click `Awake.app` → **Open** → **Open** also works.

Awake runs only in the menu bar (no Dock icon).

## Usage

- **Left-click** the menu bar cup to open the menu. **Right-click** to toggle the current mode's primary action.
- Modes:
  - *While Agent is Running* — keeps the Mac awake while a linked agent has an active session.
  - *For Duration* — countdown timer (15m / 30m / 1h / 2h / 3h), remembered across launches.
  - *While Downloading* — watches a folder (default `~/Downloads`) for unfinished downloads.
  - *Indefinitely* — until you stop it.
- Settings:
  - **General** — launch at login, notifications, remaining time in the menu bar, battery cutoff, completion grace period, display and screen saver, download folder, global shortcut, updates.
  - **Agents** — link or unlink each provider and watch live sessions.
  - **Cooling** — closed-lid cooling, fan mode, and fan diagnostics.

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
- Session events are stored as JSON files under `~/Library/Application Support/Awake/agent-sessions/v1` (permissions 0700) and are deleted as sessions end.

## Closed-lid cooling

When the lid closes with no external display connected, Awake keeps the system awake and can spin the fans to prevent heat build-up during unattended runs.

- The first activation asks for an administrator password once to install a small privileged helper at `/Library/PrivilegedHelperTools/pmgwork.awake.smc` (`root:admin`, setuid root).
- The helper holds a fan lease and watches the Awake process, so automatic fan control is restored if Awake exits or crashes.
- Options: fan mode (Maximum / Aggressive / Auto), "Exclude Normal Clamshell" (leave control to macOS when an external display is connected), and "only on AC power".
- To remove the helper completely: `sudo rm /Library/PrivilegedHelperTools/pmgwork.awake.smc`.

## Privacy

- Agent activity is detected from local hook events under `~/Library/Application Support/Awake`. Awake does not poll running processes and does not inspect your project or document files.
- Download detection only looks at file names (`.download`, `.crdownload`, `.part`, …, skipping hidden files) in the folder you choose.
- No analytics, no telemetry, no account. The only network request is the GitHub Releases update check, and only when it is enabled.

## Building from source

Requires Xcode 16 or later. Release builds are made with Xcode 27 and the macOS 27 SDK, so the app adopts the macOS 26/27 appearance and behavior changes. There are no third-party dependencies.

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

## Releasing

```sh
scripts/package.sh 0.1.2
# => dist/Awake-0.1.2.zip, dist/Awake-0.1.2.dmg, dist/Awake-0.1.2.sha256
```

Create a GitHub release with tag `v0.1.2`, keep it a **stable** release (not a draft or pre-release), and attach the ZIP. The in-app update check reads `releases/latest`, which ignores drafts and pre-releases.

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
| "Could not check for updates" | The repository must be public and have a published stable release; the check is unauthenticated |
| Fan control is unavailable | Settings → Cooling → **Install Helper** / **Update Helper** |
| Agents are not detected | Settings → Agents → **Link** for that provider, then **Test** |

## License

MIT License. See [LICENSE](LICENSE).

Copyright (c) 2026 PMGWork

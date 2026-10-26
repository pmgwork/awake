# Awake

[English](README.md) | [日本語](README.ja.md) | **简体中文**

一款 macOS 菜单栏应用：在 AI 编程代理运行期间防止 Mac 睡眠，合上盖子也能继续工作。

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## 功能

- **跟随代理保持唤醒** — 通过 Codex、Claude Code、OpenCode、Antigravity 各自的 Hook 事件进行检测，不轮询进程。
- **其他模式** — 指定时长（15 分钟～3 小时）、下载中、以及不限时。
- **散热** — 除了代理运行时合盖期间的自动散热外，还支持在任何显示环境下使用的手动散热（Apple Silicon）。合盖并连接外接显示器时，自动散热会将风扇控制交给 macOS。
- **电池保护** — 在设定的电量（关闭／5～25%，默认 20%）自动停止防止睡眠和代理散热，并把风扇恢复为自动控制。低于该电量时不会自动启动，但仍可手动启动。
- **屏幕控制** — 仅在会话期间防止显示器睡眠、屏幕保护程序和自动锁定。
- **合盖低电量模式** — 会话期间合盖时可开启 macOS 低电量模式，结束后恢复原来的设置（可选）。
- **通知** — 自动停止或保护机制失败时发出通知。
- **应用内更新** — 检查 GitHub Releases，并在应用内下载安装新版本（Sparkle，带 EdDSA 签名验证）。无需账号。

## 系统要求

- macOS 26（Tahoe）或更高版本，支持 macOS 27（Golden Gate）（macOS 27 本身仅支持 Apple Silicon）
- 合盖散热的风扇控制面向 Apple Silicon（其他功能也可在运行 macOS 26 的 Intel Mac 上使用）
- 应用界面支持英语和日语

## 安装

1. 从[最新版本](https://github.com/PMGWork/awake/releases/latest)下载 `Awake-x.y.z.zip`（每个版本还附带可直接拖入 Applications 的 `Awake-x.y.z.dmg`）
2. 解压后把 `Awake.app` 移动到 `/Applications`
3. 构建未经过公证（notarization），首次启动需要绕过一次 Gatekeeper：
   - 先尝试打开一次 `Awake.app` 并关闭警告，然后前往**系统设置 → 隐私与安全性**，滚动到**安全性**并点按 **仍要打开**，或
   - 清除 quarantine 属性：`xattr -r -d com.apple.quarantine /Applications/Awake.app`
   - 使用 DMG 时同样需要这些许可：打开磁盘映像时的提示没有「打开」按钮，请在**系统设置 → 隐私与安全性**中允许，复制到 `/Applications` 后再允许应用

Awake 只在菜单栏运行（不会显示在 Dock 中）。

测试版会在[版本列表](https://github.com/PMGWork/awake/releases)中标记为 **Pre-release**（例如 `v0.6.0-beta.1`）。在 **Settings → General → Receive Beta Updates** 中启用测试版更新后，应用内更新检查会包含测试版（默认关闭）。测试版更新源也包含稳定版，因此对应的稳定版发布后可以更新到该稳定版。关闭此设置会停止接收后续测试版更新，不会降级已安装的版本。也可以按照上述步骤手动安装。

## 使用方法

- **左键**点按菜单栏图标打开菜单，**右键**点按执行当前模式的主要操作。
- 模式
  - *代理运行时* — 已链接的代理存在活动会话时保持唤醒
  - *指定时长* — 倒计时（15 分／30 分／1 小时／2 小时／3 小时），选择会被记住
  - *下载中* — 监视指定文件夹（默认 `~/Downloads`）中未完成的下载
  - *不限时* — 直到手动停止
- 设置
  - **一般** — 语言（跟随系统、英语或日语）、登录时启动、通知、菜单栏剩余时间、更新
  - **防止睡眠** — 屏幕与屏幕保护程序、合盖运行、合盖低电量模式、电池停止阈值
  - **监视** — 链接／解除链接各代理提供方、查看活动会话、下载文件夹
  - **散热** — 自动与手动散热各自的风扇速度、代理散热选项
  - **权限** — 安装、更新或删除共享辅助工具

## 命令行

应用内置 `awake` 命令。将 Awake.app 移至 `/Applications` 后，一次性添加到 PATH：

```sh
mkdir -p "$HOME/.local/bin"
ln -s /Applications/Awake.app/Contents/Helpers/awake "$HOME/.local/bin/awake"
```

请确保 `~/.local/bin` 位于 PATH 中。如果已存在同名命令，请选择其他位置，不要覆盖。同一位置的应用更新后，链接仍然有效。删除该符号链接即可卸载命令。

```sh
awake start                 # 无限期启动
awake start --duration 30m  # 启动30分钟
awake stop                  # 停止防止睡眠
awake status                # 显示状态、模式、剩余秒数及睡眠保护运行状态
awake status --json         # JSON 状态（定时结束时间使用 ISO 8601）
awake --help
```

命令会在需要时于后台启动其所属应用，并控制菜单栏中的同一会话。`start` 选择无限期模式；`start --duration` 选择定时模式并保存时长。再次启动会替换当前会话并重置定时器。时长支持正整数加 `s`、`m` 或 `h`，最多7天。`stop` 停止防止睡眠；散热仍独立运行。CLI 启动遵循与手动启动相同的规则，包括低电量时的手动覆盖。硬件操作仍需现有授权。状态包含实际睡眠保护运行状态；即使会话处于活动状态，保护仍可能降级或失败。成功时退出码为0；输入无效、连接失败或操作被拒绝时为非0。需要应用本体及已登录的 macOS GUI 会话。

操作命令仅显示一行结果。输入错误也保持简短；使用 `awake --help` 查看完整帮助。使用 `status` 查看详情，或使用 `status --json` 获取脚本用输出。

也支持模式选择和散热控制：

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

防止睡眠模式包括 `indefinitely`（无限期）、`timer`（定时）、`agent`（代理运行时）和 `download`（下载时）。散热支持 `indefinitely`、`timer` 和 `agent`。`awake mode` 和 `awake cooling mode` 不带值时显示当前状态。模式选择与菜单一致：更改模式会停止之前的会话；手动模式等待启动，代理散热在可用时会自动进入已启动状态。`awake start --mode timer` 使用已保存的时长；以 `agent` 或 `download` 启动需要启用对应监视，无活动时等待。`awake cooling start` 使用当前散热模式。指定时长意味着 `timer`，与其他模式同时使用会被拒绝。

散热时长与应用预设一致：`5m`、`10m`、`15m` 或 `30m`；自动和手动风扇速度支持 `50`、`75` 或 `100` 百分比。启动散热或更改速度需要已安装的辅助工具；CLI 不会安装工具或请求授权。电池保护、合盖及外接显示器规则仍然适用。启动被拒绝时保留当前模式和定时器。`status` 包含嵌套的 `cooling` 状态：`armed` 表示已启动，`active` 表示当前策略要求散热，`fanControl` 表示控制器已应用的模式（`auto` 或百分比，并非实测转速）。风扇控制是异步的，请再次查看 `status` 以确认结果或错误。`waitingForActivity` 表示已启用监视的条件防止睡眠模式正在等待活动。散热与防止睡眠保持独立。

## 代理集成

Awake 会把内置的 `AwakeHookBridge` 命令（安装在 `~/Library/Application Support/Awake/bin`）写入各代理自身的配置文件。

| 提供方 | 配置文件 |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| OpenCode | `~/.config/opencode/opencode.json`（或 `opencode.jsonc`），以及 `~/Library/Application Support/Awake/integrations/opencode` 中的插件 |
| Antigravity | `~/.gemini/config/hooks.json` |

- 只添加或删除 Awake 自己的条目（带有 `--owner pmgwork.awake`）。
- 首次修改前，会在原文件旁生成 `<文件名>.awake-backup` 备份。
- 在「设置 → 代理」中**解除链接**，只会删除 Awake 的条目。
- 监视使用文件系统变更通知和会话缓存，降低空闲时的 CPU 占用。关闭监视后会停止监听，但自动散热所需的代理监视仍会继续。
- 会话事件以 JSON 形式保存在 `~/Library/Application Support/Awake/agent-sessions/v1`（权限 0700）。会话结束后保留每个会话的最新事件，以阻止延迟的旧事件使会话重新变为活动状态，并在新一轮开始时覆盖。

## 散热

散热与防止睡眠相互独立。在菜单中选择**散热模式**，然后点按**开始散热**。可在「设置 → 散热」中分别设置**自动散热**（代理运行时）与**手动散热**（不限时、指定时长）的风扇速度。新安装时两者默认为 100%，已有的风扇速度设置会迁移到两者。散热停止或暂停时，由 macOS 控制风扇。

| 模式 | 行为 |
|---|---|
| 不限时 | 风扇持续运转，直到手动停止散热 |
| 指定时长 | 5／10／15／30 分钟后将风扇交还给 macOS |
| 代理运行时 | 受监视的代理运行且合盖期间。选择后即开始，可在菜单中暂停或恢复（默认） |

- 在「设置 → 权限」中查看权限状态，并安装或更新。合盖运行与风扇控制共用同一个管理员权限辅助工具。
- 首次启用时会请求一次管理员密码，安装辅助工具 `/Library/PrivilegedHelperTools/pmgwork.awake.smc`（`root:admin`，setuid root）。
- 该辅助工具持有风扇租约并监视 Awake 进程；如果 Awake 退出或崩溃，会自动把风扇恢复为自动控制。
- 电池电量达到停止阈值时代理散热也会停止，并发送通知。在电量恢复或接上电源适配器之前无法恢复。「不限时」和「指定时长」的散热由你手动开始，因此会继续运行。「不限时」和「指定时长」的散热不会在重新启动后保留。
- 「代理运行时」选项：「仅在连接电源时」。代理运行时的散热仅在合盖期间生效。
- 合盖并连接外接显示器时，代理运行时的自动散热会将风扇控制交给 macOS，而手动散热会继续运行。此状态下 Awake 也不会覆盖合盖睡眠或启用低电量模式。退出此状态后，如果代理仍在运行，自动散热会恢复。
- 要删除辅助工具，请在「设置 → 权限」中使用「删除…」。Awake 会停止当前会话，将风扇恢复为自动控制，然后删除共享辅助工具并关闭合盖运行与散热。

## 隐私

- 代理检测只使用 `~/Library/Application Support/Awake` 下的本地 Hook 事件，不轮询进程，也不扫描你的项目或文档文件。
- 下载检测只查看所选文件夹中的文件名（`.download`、`.crdownload`、`.part` 等，跳过隐藏文件）和修改时间。子文件夹中的此类文件仅在最近 10 分钟内有更新时才计入，因此解压后残留的文件不会阻止 Mac 睡眠。
- 没有分析、遥测或账号。网络请求仅限于读取 `raw.githubusercontent.com` 上的更新源，以及在你同意更新后从 GitHub Releases 下载更新。不会发送匿名系统分析数据。

## 从源码构建

需要 Xcode 16 或更高版本。发布构建使用 Xcode 27 与 macOS 27 SDK，以采用 macOS 26/27 的外观与行为变化。唯一的第三方依赖是用于应用内更新的 [Sparkle](https://sparkle-project.org)（通过 Swift Package Manager 获取）。

```sh
git clone https://github.com/PMGWork/awake.git
cd awake
open awake.xcodeproj
```

也可以在命令行构建：

```sh
xcodebuild -project awake.xcodeproj -scheme awake -configuration Debug build
```

单元测试请在 Xcode 中执行 **Product ▸ Test**（目标 `awakeTests`）。应用目标使用文件系统同步分组，因此 `awake/` 下新增的文件会被自动识别。

发布（分发）流程记录在 `docs/DISTRIBUTION.md`。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `awake/` | 应用源码（Models、Services、State、Views、本地化） |
| `AwakeHookBridge/` | 由代理 Hook 调用的命令行工具 |
| `awakeTests/` | 单元测试 |
| `docs/` | 发布说明与设计文档 |
| `scripts/` | 打包与数据重置脚本 |

## 常见问题

| 现象 | 处理方法 |
| --- | --- |
| 首次启动被 macOS 阻止 | 系统设置 → 隐私与安全性 → **仍要打开**，或清除 quarantine 属性（见「安装」） |
| 应用内更新失败 | 从最新版本下载并手动重新安装 |
| 无法使用风扇控制 | 设置 → 权限 → **安装**／**更新** |
| 检测不到代理 | 在设置 → 代理中**链接**，然后执行**测试** |

## 许可证

MIT 许可证。详见 [LICENSE](LICENSE)。

Copyright (c) 2026 PMGWork

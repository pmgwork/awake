# Awake

[English](README.md) | [日本語](README.ja.md) | **简体中文**

一款 macOS 菜单栏应用：在 AI 编程代理运行期间防止 Mac 睡眠，合上盖子也能继续工作。

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## 功能

- **跟随代理保持唤醒** — 通过 Codex、Claude Code、OpenCode、Antigravity 各自的 Hook 事件进行检测，不轮询进程。
- **其他模式** — 指定时长（15 分钟～3 小时）、下载中、以及不限时。
- **散热** — 在代理运行等情况下运转风扇，避免热量积聚。默认仅在合盖时生效（Apple Silicon）。
- **电池保护** — 在设定的电量（关闭／5～25%，默认 20%）自动停止，并把风扇恢复为自动控制。低于该电量时不会自动启动，但仍可手动启动。
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

测试版会在[版本列表](https://github.com/PMGWork/awake/releases)中标记为 **Pre-release**（例如 `v0.6.0-beta.1`）。请按照上述步骤手动下载并安装。应用内更新仅检查稳定版；对应的稳定版发布后，测试版也可以更新到该稳定版。

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
  - **散热** — 风扇速度、代理散热选项
  - **权限** — 安装、更新或删除共享辅助工具

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
- 会话事件以 JSON 形式保存在 `~/Library/Application Support/Awake/agent-sessions/v1`（权限 0700）。会话结束后保留每个会话的最新事件，以阻止延迟的旧事件使会话重新变为活动状态，并在新一轮开始时覆盖。

## 散热

散热与防止睡眠相互独立。在菜单中选择**散热模式**，然后点按**开始散热**。所有模式都会按「设置 → 散热」中的风扇速度（默认 100%）运转风扇。散热停止或暂停时，由 macOS 控制风扇。

| 模式 | 行为 |
|---|---|
| 不限时 | 风扇持续运转，直到手动停止散热 |
| 指定时长 | 5／10／15／30 分钟后将风扇交还给 macOS |
| 代理运行时 | 受监视的代理运行期间（默认仅在合盖时）。选择后即开始，可在菜单中暂停或恢复（默认） |

- 在「设置 → 权限」中查看权限状态，并安装或更新。合盖运行与风扇控制共用同一个管理员权限辅助工具。
- 首次启用时会请求一次管理员密码，安装辅助工具 `/Library/PrivilegedHelperTools/pmgwork.awake.smc`（`root:admin`，setuid root）。
- 该辅助工具持有风扇租约并监视 Awake 进程；如果 Awake 退出或崩溃，会自动把风扇恢复为自动控制。
- 电池电量达到停止阈值时散热也会停止。「不限时」和「指定时长」的散热不会在重新启动后保留。
- 「代理运行时」选项：「仅在合盖时」（默认开启）、「连接外接显示器时交给 macOS 控制风扇」（合盖并连接外接显示器时）、「仅在连接电源时」
- 要删除辅助工具，请在「设置 → 权限」中使用「删除…」。Awake 会停止当前会话，将风扇恢复为自动控制，然后删除共享辅助工具并关闭合盖运行与散热。

## 隐私

- 代理检测只使用 `~/Library/Application Support/Awake` 下的本地 Hook 事件，不轮询进程，也不扫描你的项目或文档文件。
- 下载检测只查看所选文件夹中的文件名（`.download`、`.crdownload`、`.part` 等，跳过隐藏文件）。
- 没有分析、遥测或账号。网络请求仅限于读取 GitHub 的 `releases/latest` 进行更新检查，以及在你同意更新后下载更新。不会发送匿名系统分析数据。

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

# Awake

[English](README.md) | [日本語](README.ja.md) | **简体中文**

一款 macOS 菜单栏应用：在 AI 编程代理运行期间防止 Mac 睡眠，合上盖子也能继续工作。

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## 功能

- **跟随代理保持唤醒** — 通过 Codex、Claude Code、OpenCode、Antigravity 各自的 Hook 事件进行检测，不轮询进程。
- **其他模式** — 指定时长（15 分钟～3 小时）、下载中、以及不限时。
- **完成后的宽限期** — 最后一个代理或下载结束后，再保持 1～5 分钟不睡眠。
- **合盖散热** — 未连接外接显示器且合上盖子时，可让风扇运转，避免热量积聚（Apple Silicon）。
- **电池保护** — 在设定的电量（关闭／5～25%，默认 20%）自动停止，并把风扇恢复为自动控制。
- **屏幕控制** — 仅在会话期间防止显示器睡眠、屏幕保护程序和自动锁定。
- **全局快捷键** — 录制组合键后，可在任意应用中执行菜单栏的主要操作。
- **通知** — 自动停止或保护机制失败时发出通知。
- **应用内更新** — 检查 GitHub Releases，并在应用内下载安装新版本（Sparkle，带 EdDSA 签名验证）。无需账号。

## 系统要求

- macOS 13（Ventura）或更高版本，支持 macOS 27（Golden Gate）（macOS 27 本身仅支持 Apple Silicon）
- 合盖散热的风扇控制面向 Apple Silicon（其他功能在运行 macOS 13〜26 的 Intel Mac 上也可使用）
- 应用界面支持英语和日语

## 安装

1. 从[最新版本](https://github.com/PMGWork/awake/releases/latest)下载 `Awake-x.y.z.zip`
2. 解压后把 `Awake.app` 移动到 `/Applications`
3. 构建未经过公证（notarization），首次启动需要绕过一次 Gatekeeper：
   - macOS 15 或更高版本（含 26/27）：先尝试打开一次 `Awake.app` 并关闭警告，然后前往**系统设置 → 隐私与安全性**，滚动到**安全性**并点按 **仍要打开**，或
   - 清除 quarantine 属性：`xattr -r -d com.apple.quarantine /Applications/Awake.app`
   - macOS 14 及更早版本也可右键点按 `Awake.app` → **打开** → **打开**
4. 也可以使用 Homebrew 安装（需要先 tap）：
   ```sh
   brew tap pmgwork/tap
   brew install --cask awake
   ```
   首次启动同样需要绕过一次 Gatekeeper。安装后 Awake 会在应用内自行更新，`brew upgrade --cask awake` 是可选的。

Awake 只在菜单栏运行（不会显示在 Dock 中）。

## 使用方法

- **左键**点按菜单栏图标打开菜单，**右键**点按执行当前模式的主要操作。
- 模式
  - *代理运行时* — 已链接的代理存在活动会话时保持唤醒
  - *指定时长* — 倒计时（15 分／30 分／1 小时／2 小时／3 小时），选择会被记住
  - *下载中* — 监视指定文件夹（默认 `~/Downloads`）中未完成的下载
  - *不限时* — 直到手动停止
- 设置
  - **一般** — 登录时启动、通知、菜单栏剩余时间、电池停止阈值、完成后宽限期、屏幕与屏幕保护程序、下载文件夹、全局快捷键、更新
  - **代理** — 链接／解除链接各提供方，并查看活动会话
  - **散热** — 合盖散热、风扇模式、风扇诊断

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
- 会话事件以 JSON 形式保存在 `~/Library/Application Support/Awake/agent-sessions/v1`（权限 0700），会话结束后会被删除。

## 合盖散热

未连接外接显示器并合上盖子时，Awake 会防止睡眠，并可通过风扇运转避免热量积聚。

- 首次启用时会请求一次管理员密码，安装辅助工具 `/Library/PrivilegedHelperTools/pmgwork.awake.smc`（`root:admin`，setuid root）。
- 该辅助工具会监视 Awake 进程；如果 Awake 退出或崩溃，会自动把风扇恢复为自动控制。
- 选项：风扇模式（最大／强力／自动）、排除普通合盖模式（连接外接显示器时交给 macOS 控制）、仅在连接电源时启用
- 如需彻底删除辅助工具：`sudo rm /Library/PrivilegedHelperTools/pmgwork.awake.smc`

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

## 发布

首次需要生成签名密钥：用 `dist/sparkle-tools/bin/generate_keys` 生成 Sparkle 的 EdDSA 密钥并妥善保管（工具会在首次打包时自动下载）。公钥已写入 `awake/Info.plist` 的 `SUPublicEDKey`。如果私钥丢失，现有用户将无法再收到应用内更新。

```sh
scripts/package.sh 0.1.2
# => dist/Awake-0.1.2.zip, dist/Awake-0.1.2.dmg, dist/Awake-0.1.2.sha256, dist/appcast.xml
```

可以事先准备 `dist/release-notes-v0.1.2.md`，其内容会嵌入 appcast 并显示在更新窗口中。

创建标签为 `v0.1.2` 的 GitHub Release，保持为 **stable**（不是 draft，也不是 pre-release），并附上 ZIP 和 `appcast.xml`（也可附上 DMG 和 `.sha256` 供手动下载）。更新检查读取 `https://github.com/PMGWork/awake/releases/latest/download/appcast.xml`，因此最新的 stable 版本必须附带 `appcast.xml`。详见 `docs/DISTRIBUTION.md`。

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
| 应用内更新失败 | 仓库需要是公开的，且最新的 **stable** 版本必须附带 `appcast.xml`（见「发布」） |
| 无法使用风扇控制 | 设置 → 散热 → **安装辅助工具**／**更新辅助工具** |
| 检测不到代理 | 在设置 → 代理中**链接**，然后执行**测试** |

## 许可证

MIT 许可证。详见 [LICENSE](LICENSE)。

Copyright (c) 2026 PMGWork

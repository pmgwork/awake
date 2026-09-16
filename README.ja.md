# Awake

[English](README.md) | **日本語** | [简体中文](README.zh-CN.md)

AIコーディングエージェントの実行中、Macのスリープを防ぐメニューバーアプリです。蓋を閉じたままでも動作します。

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Latest release](https://img.shields.io/github/v/release/PMGWork/awake)
![License](https://img.shields.io/badge/license-MIT-blue)

## 主な機能

- **エージェント連動** — Codex、Claude Code、OpenCode、Antigravity のフックイベントを利用して検出します。プロセスのポーリングは行いません。
- **その他のモード** — 指定時間（15分〜3時間）、ダウンロード中、無期限の3種類。
- **完了後の猶予時間** — エージェントやダウンロードが終わってからさらに1〜5分間スリープを防ぎます。
- **閉蓋冷却** — 外部ディスプレイを接続せずに蓋を閉じたとき、ファンを回して熱のこもりを防ぎます（Apple Silicon）。
- **バッテリー保護** — 指定した残量（オフ／5〜25%、初期値20%）で自動停止し、ファンも自動制御へ戻します。この残量以下では自動での開始は行われませんが、手動で開始することはできます。
- **画面の制御** — セッション中だけ、ディスプレイのスリープ・スクリーンセーバー・自動ロックを防止できます。
- **通知** — 自動停止や保護機構の失敗時に通知します。
- **アプリ内アップデート** — GitHub Releases を確認し、新しい版はアプリ内でダウンロードしてインストールします（Sparkle・EdDSA 署名検証つき）。アカウントは不要です。

## 動作環境

- macOS 26（Tahoe）以降。macOS 27（Golden Gate）に対応しています（macOS 27 自体は Apple Silicon 専用です）
- 閉蓋冷却のファン制御は Apple Silicon 向けです（その他の機能は macOS 26 の Intel Mac でも動作します）
- アプリの表示は英語と日本語に対応しています

## インストール

1. [最新リリース](https://github.com/PMGWork/awake/releases/latest) から `Awake-x.y.z.zip` をダウンロード（各リリースには、Applications へドラッグするだけの `Awake-x.y.z.dmg` も添付されます）
2. 展開して `Awake.app` を `/Applications` へ移動
3. 公証（notarization）を行っていないため、初回起動時のみ Gatekeeper の回避操作が必要です
   - 一度 `Awake.app` を開こうとして警告を閉じ、**システム設定 → プライバシーとセキュリティ** の **セキュリティ** 欄で **このまま開く** をクリック
   - または quarantine 属性を削除: `xattr -r -d com.apple.quarantine /Applications/Awake.app`
   - DMG を使う場合も同じ許可が必要です。ディスクイメージを開くときの警告には「開く」ボタンがないため **システム設定 → プライバシーとセキュリティ** から許可し、`/Applications` へコピーした後にアプリ側も許可します

Awake はメニューバー専用アプリです（Dock にアイコンは表示されません）。

## 使い方

- メニューバーのカップを**左クリック**でメニュー、**右クリック**で現在のモードの主操作を切り替えます。
- モード
  - *エージェント実行中* — 連携したエージェントのセッションが動いている間、スリープを防ぎます
  - *時間を指定* — タイマー（15分／30分／1時間／2時間／3時間）。選択は次回起動時も保持されます
  - *ダウンロード中* — 指定フォルダ（初期値 `~/Downloads`）の未完了ダウンロードを監視します
  - *無期限* — 手動で停止するまで
- 設定
  - **一般** — ログイン時に起動、通知、バッテリー停止、アップデート
  - **セッション** — 完了後の猶予時間、メニューバーの残り時間表示、画面とスクリーンセーバー、ダウンロードフォルダ
  - **エージェント** — プロバイダーの連携／解除と稼働中セッションの表示
  - **冷却** — 閉蓋冷却、ファンモード、ファンの診断

## エージェント連携

同梱の `AwakeHookBridge` コマンド（`~/Library/Application Support/Awake/bin` に配置）を、各エージェント自身の設定ファイルへ追加します。

| プロバイダー | 設定ファイル |
| --- | --- |
| Codex | `~/.codex/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| OpenCode | `~/.config/opencode/opencode.json`（または `opencode.jsonc`）と、`~/Library/Application Support/Awake/integrations/opencode` のプラグイン |
| Antigravity | `~/.gemini/config/hooks.json` |

- 追加・削除するのは Awake が所有するエントリ（`--owner pmgwork.awake` 付き）だけです。
- 初回変更時に、元のファイルを `<ファイル名>.awake-backup` として隣にバックアップします。
- 設定 → エージェントの**連携解除**で、Awake のエントリだけを削除できます。
- セッションイベントは `~/Library/Application Support/Awake/agent-sessions/v1`（パーミッション 0700）に JSON で保存され、セッション終了時に削除されます。

## 閉蓋冷却

外部ディスプレイを接続せずに蓋を閉じたとき、スリープを防ぎつつファンを回して熱のこもりを防ぎます。

- 初回のみ管理者パスワードを求め、専用ヘルパー `/Library/PrivilegedHelperTools/pmgwork.awake.smc`（`root:admin`、setuid root）をインストールします。
- ヘルパーは Awake プロセスを監視し、Awake が終了・クラッシュした場合はファンを自動制御へ戻します。
- オプション: ファンモード（最大／強冷却／自動）、通常のクラムシェルモードを除外（外部ディスプレイ接続時は macOS に任せる）、AC電源接続時のみ有効
- ヘルパーを完全に削除する場合: `sudo rm /Library/PrivilegedHelperTools/pmgwork.awake.smc`

## プライバシー

- エージェントの検出は `~/Library/Application Support/Awake` 配下のローカルなフックイベントのみを使用します。プロセスのポーリングや、プロジェクト・書類ファイルの走査は行いません。
- ダウンロードの検出は、指定フォルダ内のファイル名（`.download`、`.crdownload`、`.part` など。隠しファイルは対象外）のみを参照します。
- 解析・テレメトリー・アカウントはありません。ネットワーク通信は、GitHub の `releases/latest` の確認と、更新に同意したときのダウンロードだけです。匿名のシステムプロファイリングは送信しません。

## ソースからビルド

Xcode 16 以降が必要です。リリースビルドは Xcode 27 と macOS 27 SDK で作成し、macOS 26/27 の外観・挙動の変更に追随します。外部依存は、アプリ内アップデート用の [Sparkle](https://sparkle-project.org)（Swift Package Manager 経由）だけです。

```sh
git clone https://github.com/PMGWork/awake.git
cd awake
open awake.xcodeproj
```

コマンドラインからビルドする場合:

```sh
xcodebuild -project awake.xcodeproj -scheme awake -configuration Debug build
```

ユニットテストは Xcode の **Product ▸ Test**（ターゲット `awakeTests`）で実行します。アプリのターゲットはファイル同期グループを使用しているため、`awake/` 配下に追加したファイルは自動的に認識されます。

リリース（配布）手順は `docs/DISTRIBUTION.md` にまとめています。

## プロジェクト構成

| パス | 内容 |
| --- | --- |
| `awake/` | アプリ本体（Models、Services、State、Views、ローカライズ） |
| `AwakeHookBridge/` | エージェントのフックから呼ばれるコマンドラインツール |
| `awakeTests/` | ユニットテスト |
| `docs/` | 配布手順と設計資料 |
| `scripts/` | パッケージ作成とデータリセット用スクリプト |

## トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| 初回起動時に macOS にブロックされる | システム設定 → プライバシーとセキュリティ → **このまま開く**、または quarantine 属性を削除（インストール参照） |
| アプリ内アップデートに失敗する | 最新リリースからダウンロードして手動で入れ直す |
| ファン制御が使えない | 設定 → 冷却 → **ヘルパーをインストール**／**ヘルパーを更新** |
| エージェントが検出されない | 設定 → エージェントで **連携** し、**テスト** を実行 |

## ライセンス

MIT ライセンスです。詳細は [LICENSE](LICENSE) を参照してください。

Copyright (c) 2026 PMGWork

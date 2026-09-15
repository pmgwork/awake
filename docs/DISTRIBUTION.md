# 配布手順 (有料アカウントなし)

公証なし・GitHub Releases配布が前提。アプリ内更新チェック (`AppUpdateService`)
はこの運用に合わせてある。

## 前提

- ツールチェーン: リリースビルドは Xcode 27（macOS 27 SDK）で作成する。
  `scripts/package.sh` は `/Applications/Xcode.app` を既定で使い、
  `DEVELOPER_DIR` を設定すれば任意の Xcode に切り替えられる。
- アーキテクチャ: Release は universal（arm64 + x86_64）。macOS 27 は
  Apple Silicon 専用だが、macOS 13〜26 の Intel Mac 向けスライスも同梱する。
- 署名: ローカルの Apple Development / ad-hoc で可。他人のMacでは
  Gatekeeper警告が出る (仕様)。Developer ID・公証は有料Program必須のため対象外。
- タグ形式: `vX.Y.Z` (例 `v0.1.1`)。`AppUpdateService` が先頭 `v` を剥がして
  `CFBundleShortVersionString` と比較する。

## リリース手順

1. 版数を決める: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   (Xcode > Target awake > General、現在 `0.1.1`)
2. パッケージ作成:

   ```sh
   scripts/package.sh 0.1.1
   # => dist/Awake-0.1.1.zip (+ .dmg), dist/Awake-0.1.1.sha256
   ```

3. GitHubでタグ + Release作成:
   - タグ `v0.1.1` をpush
   - Release名 `Awake v0.1.1`、Notesに変更点（**英語**）とSHA256を記載
   - `dist/Awake-0.1.1.zip` (必須) を添付。DMGは任意。
   - **Stable releaseとして公開** (pre-release/draftにしない。
     `AppUpdateService` はstableな `releases/latest` のみ見る)
4. 動作確認: 別Mac or 新規ユーザでZIP展開→初回起動→オンボーディング→
   設定 > Software Updates > Check Now で新版検出を確認。
   macOS 27（Apple Silicon）で温度表示・スリープ防止・ファン制御が
   動作することも確認する。

## 利用者向け (Gatekeeper回避)

初回のみいずれか (macOS 15 以降。macOS 14 以前は右クリック → 開く → 開くも可):

- 一度起動を試して警告を閉じ、システム設定 → プライバシーとセキュリティ →
  セキュリティ欄の「このまま開く」をクリック (推奨、GUIのみで完結)
- または: `xattr -r -d com.apple.quarantine /Applications/Awake.app`

## 有料アカウント取得後の切替メモ

- Developer ID Applicationで署名 → `notarytool submit` → `stapler staple`
- 上記が済んだら本手順の「Gatekeeper回避」節は削除可
- 将来的にSparkleへ移行する場合もRelease添付の運用はそのまま使える

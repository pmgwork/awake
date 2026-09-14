# 配布手順 (有料アカウントなし)

公証なし・GitHub Releases配布が前提。アプリ内更新チェック (`AppUpdateService`)
はこの運用に合わせてある。

## 前提

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

## 利用者向け (Gatekeeper回避)

初回のみいずれか:

- 右クリック → 開く → 開く (推奨、GUIのみで完結)
- または: `xattr -d com.apple.quarantine /Applications/Awake.app`

## 有料アカウント取得後の切替メモ

- Developer ID Applicationで署名 → `notarytool submit` → `stapler staple`
- 上記が済んだら本手順の「Gatekeeper回避」節は削除可
- 将来的にSparkleへ移行する場合もRelease添付の運用はそのまま使える

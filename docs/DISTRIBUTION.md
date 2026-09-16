# 配布手順 (有料アカウントなし)

公証なし・GitHub Releases配布が前提。アプリ内アップデートは Sparkle 2
（`awake/Services/AppUpdater.swift`、フィードは `releases/latest` の `appcast.xml`）
が担当する。

## 前提

- ツールチェーン: リリースビルドは Xcode 27（macOS 27 SDK）で作成する。
  `scripts/package.sh` は `/Applications/Xcode.app` を既定で使い、
  `DEVELOPER_DIR` を設定すれば任意の Xcode に切り替えられる。
- アーキテクチャ: Release は universal（arm64 + x86_64）。macOS 27 は
  Apple Silicon 専用だが、macOS 13〜26 の Intel Mac 向けスライスも同梱する。
- 署名: ローカルの Apple Development 署名で可。Hardened Runtime と
  Library Validation の関係で、Sparkle.framework をロードするには
  Apple Development 署名が必要（ad-hoc 署名ではロードできない）。
  他人のMacではGatekeeper警告が出る (仕様)。Developer ID・公証は
  有料Program必須のため対象外。
- タグ形式: `vX.Y.Z` (例 `v0.1.3`)。Sparkle は `CFBundleVersion` で新旧を比較し、
  `scripts/package.sh` が `CURRENT_PROJECT_VERSION` に版数を入れる。

## 署名鍵 (初回のみ)

- 生成: `dist/sparkle-tools/bin/generate_keys`
  - ツールは初回の `scripts/package.sh` が `dist/sparkle-tools/` に展開する。
  - 秘密鍵はログイン Keychain（account `ed25519`）に保存される。
  - 公開鍵（例 `0Fy0...LU8=`）は `awake/Info.plist` の `SUPublicEDKey` に埋め込む。
- バックアップ: `dist/sparkle-tools/bin/generate_keys -x <file>` で秘密鍵を
  エクスポートし、安全な場所に保管する。復元は `-f <file>`。
- **秘密鍵を失うと、既存ユーザーにアプリ内アップデートを配布できなくなる**
  （手動ダウンロードへ戻す必要がある）。鍵のローテーションは
  Developer ID 署名の DMG が必要になるため、実質不可と考えてよい。
- `awake/Info.plist` の Sparkle 設定:
  - `SUFeedURL` = `https://github.com/PMGWork/awake/releases/latest/download/appcast.xml`
  - `SUEnableAutomaticChecks` = true（許可ダイアログを出さない。アプリ内の
    「アップデートを自動で確認」が `SPUUpdater.automaticallyChecksForUpdates` を操作する）
  - `SUVerifyUpdateBeforeExtraction` = true（署名検証を展開前に行う）
  - `SUEnableSystemProfiling` = false（匿名プロファイリングを送らない）

## リリース手順

1. 版数を決める: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   (Xcode > Target awake > General、現在 `0.1.2`)。`scripts/package.sh` が
   引数の版数で両方を上書きするため、通常はプロジェクト側の変更は不要。
2. リリースノート（**英語**）を `dist/release-notes-v<version>.md` として用意する。
   `generate_appcast` が同じ名前の ZIP に紐づけて appcast へ埋め込み、
   Sparkle の更新画面に表示する（任意だが推奨）。
3. パッケージ作成:

   ```sh
   scripts/package.sh 0.1.3
   # => dist/Awake-0.1.3.zip (+ .dmg), dist/Awake-0.1.3.sha256, dist/appcast.xml
   ```

   初回は Sparkle 2.10.0 のツールを `dist/sparkle-tools/` にダウンロードし、
   EdDSA 鍵（Keychain）で ZIP に署名して `appcast.xml` を生成する。
4. GitHubでタグ + Release作成:
   - タグ `v0.1.3` をpush
   - Release名 `Awake v0.1.3`、Notesに変更点（**英語**）とSHA256を記載
   - 添付: `dist/Awake-0.1.3.zip` と `dist/appcast.xml`（両方必須）。
     DMG・`.sha256` は任意（手動ダウンロード用）
   - **Stable releaseとして公開** (pre-release/draftにしない。`SUFeedURL` は
     `releases/latest` を指すため、draft/pre-release は配信対象外)
5. 動作確認: Sparkle 導入版（0.1.3 以降）を入れた確認用Macで
   設定 > Software Updates > Check Now → 更新が見つかる → Install で
   置き換えと再起動が完了することを確認する。初回の Sparkle 導入版
   (0.1.3) から次版への更新が最初の実地テストになる。

## Homebrew Tap (任意)

- `PMGWork/homebrew-tap` の `Casks/awake.rb` を配布している。

  ```sh
  brew tap pmgwork/tap
  brew install --cask awake
  ```

- 版数を上げたら `scripts/update-cask.sh <version>` で cask を更新する
  （リリースの `.sha256` を読んで version と sha256 を書き換える）。
- Homebrew 5.0 以降は未公証アプリの cask に quarantine が必ず付与され、
  `--no-quarantine` も廃止された。そのため cask 経由でも初回起動時は
  利用者による Gatekeeper 回避が必要（アプリ内更新は quarantine の
  影響を受けないため、2回目以降は brew 不要）。

## 利用者向け (Gatekeeper回避)

初回のみいずれか (macOS 15 以降。macOS 14 以前は右クリック → 開く → 開くも可):

- 一度起動を試して警告を閉じ、システム設定 → プライバシーとセキュリティ →
  セキュリティ欄の「このまま開く」をクリック (推奨、GUIのみで完結)
- または: `xattr -r -d com.apple.quarantine /Applications/Awake.app`

## 有料アカウント取得後の切替メモ

- Developer ID Applicationで署名 → `notarytool submit` → `stapler staple`
- 上記が済んだら本手順の「Gatekeeper回避」節は削除可
- Sparkle の EdDSA 鍵はそのまま使い続けられる（ローテーション不要）。
  公証済みになれば `SUVerifyUpdateBeforeExtraction` を維持したまま、
  Developer ID 署名 DMG 経由で鍵の変更も可能になる。

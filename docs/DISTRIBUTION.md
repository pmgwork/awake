# 配布手順 (有料アカウントなし)

公証なし・GitHub Releases配布が前提。アプリ内アップデートは Sparkle 2
（`awake/Services/AppUpdater.swift`、フィードは `releases/latest` の `appcast.xml`）
が担当する。

## 前提

- ツールチェーン: リリースビルドは Xcode 27（macOS 27 SDK）で作成する。
  `scripts/package.sh` は `/Applications/Xcode.app` を既定で使い、
  `DEVELOPER_DIR` を設定すれば任意の Xcode に切り替えられる。
- アーキテクチャ: Release は universal（arm64 + x86_64）。macOS 27 は
  Apple Silicon 専用だが、macOS 26 の Intel Mac 向けスライスも同梱する。
- 署名: ローカルの Apple Development 署名で可。Hardened Runtime と
  Library Validation の関係で、Sparkle.framework をロードするには
  Apple Development 署名が必要（ad-hoc 署名ではロードできない）。
  他人のMacではGatekeeper警告が出る (仕様)。Developer ID・公証は
  有料Program必須のため対象外。ブラウザでダウンロードした DMG も
  未公証のため、初回マウント時に Gatekeeper の確認が出る
  （システム設定 → プライバシーとセキュリティ →「このまま開く」で許可できる）。
- タグ形式: `vX.Y.Z` (例 `v0.2.0`)。Sparkle は `CFBundleVersion` で新旧を比較し、
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
   (Xcode > Target awake > General、現在 `0.2.0`)。`scripts/package.sh` が
   引数の版数で両方を上書きするため、通常はプロジェクト側の変更は不要。
2. リリースノート（**英語**）を `dist/release-notes-v<version>.md` として用意する。
   `generate_appcast` が同じ名前の ZIP に紐づけて appcast へ埋め込み、
   Sparkle の更新画面に表示する（任意だが推奨）。
3. パッケージ作成:

   ```sh
   scripts/package.sh 0.2.0
   # => dist/Awake-0.2.0.zip (+ .dmg), dist/Awake-0.2.0.sha256, dist/appcast.xml
   ```

   初回は Sparkle 2.10.0 のツールを `dist/sparkle-tools/` にダウンロードし、
   EdDSA 鍵（Keychain）で ZIP に署名して `appcast.xml` を生成する。
   DMG は `Awake.app` と `Applications` ショートカットを並べた
   ドラッグ&ドロップ用レイアウト（640×400、アイコン 128px）で作成する。
   レイアウトは Finder 経由で `.DS_Store` に書き込むため、GUI セッションが
   ない場合はレイアウトなしの DMG にフォールバックする。
4. リリース作成（`scripts/release.sh` 推奨）:

   ```sh
   scripts/release.sh 0.2.0            # ビルド→タグ→draft Release作成
   scripts/release.sh --publish 0.2.0  # 添付とノートを確認して公開
   ```

   `release.sh` は次を自動化する:
   - クリーンな作業ツリーと `origin/main` との同期を確認（未pushのビルドを防ぐ）
   - `scripts/package.sh <version>` の実行（`--skip-build` で省略可）
   - annotated タグ `v0.2.0` の作成と push
   - draft Release（名前 `Awake v0.2.0`）に `Awake-0.2.0.zip` と
     `appcast.xml`（両方必須）、あれば `.dmg` と `.sha256` も添付。
     `dist/release-notes-v0.2.0.md` があれば SHA256 を追記して Notes に使う
   - `--publish` で `--draft=false --latest` を実行し、**stable** として公開
     （`SUFeedURL` は `releases/latest` を指すため、draft/pre-release は
     配信対象外。公開前に必須アセットの有無も確認する）

   実行内容だけ確認したい場合は `--dry-run` を使う。

   手動で行う場合: タグ `v0.2.0` をpushし、Release名 `Awake v0.2.0`、Notesに
   変更点（**英語**）とSHA256を記載。添付は zip と `appcast.xml` が必須、
   `.dmg` と `.sha256` も推奨（手動ダウンロード用）。
5. 動作確認: Sparkle 導入版（0.2.0 以降）を入れた確認用Macで
   設定 > Software Updates > Check Now → 更新が見つかる → Install で
   置き換えと再起動が完了することを確認する。初回の Sparkle 導入版
   (0.2.0) から次版への更新が最初の実地テストになる。

## 利用者向け (Gatekeeper回避)

初回のみいずれか:

- 一度起動を試して警告を閉じ、システム設定 → プライバシーとセキュリティ →
  セキュリティ欄の「このまま開く」をクリック (推奨、GUIのみで完結)
- または: `xattr -r -d com.apple.quarantine /Applications/Awake.app`

## 有料アカウント取得後の切替メモ

- Developer ID Applicationで署名 → `notarytool submit` → `stapler staple`
- 上記が済んだら本手順の「Gatekeeper回避」節は削除可
- Sparkle の EdDSA 鍵はそのまま使い続けられる（ローテーション不要）。
  公証済みになれば `SUVerifyUpdateBeforeExtraction` を維持したまま、
  Developer ID 署名 DMG 経由で鍵の変更も可能になる。

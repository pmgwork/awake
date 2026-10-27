# 配布手順 (有料アカウントなし)

公証なし・GitHub Releases配布が前提。アプリ内アップデートは Sparkle 2
（`awake/Services/AppUpdater.swift`、フィードは専用の `update-feeds` ブランチ）
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
- タグ形式: 安定版は `vX.Y.Z`、ベータ版は `vX.Y.Z-beta.N`（N は 1〜255）。Sparkle は `CFBundleVersion` で新旧を比較し、
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
  - `SUFeedURL` = `https://raw.githubusercontent.com/PMGWork/awake/update-feeds/stable.xml`
  - `SUEnableAutomaticChecks` = true（許可ダイアログを出さない。アプリ内の
    「アップデートを自動で確認」が `SPUUpdater.automaticallyChecksForUpdates` を操作する）
  - `SUVerifyUpdateBeforeExtraction` = true（署名検証を展開前に行う）
  - `SUEnableSystemProfiling` = false（匿名プロファイリングを送らない）

## リリース手順

1. 版数を決める: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   (Xcode > Target awake > General)。`scripts/package.sh` が
   引数の版数で両方を上書きするため、プロジェクト側の値は更新しなくてよい。
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
   - クリーンな作業ツリーと 配布元（正式版は `origin/main`、ベータ版は `origin/develop`）との同期を確認（未pushのビルドを防ぐ）
   - `scripts/package.sh <version>` の実行（`--skip-build` で省略可）
   - annotated タグ `v0.2.0` の作成と push
   - draft Release（名前 `Awake v0.2.0`）に `Awake-0.2.0.zip` と
     `appcast.xml`（両方必須）、あれば `.dmg` と `.sha256` も添付。
     `dist/release-notes-v0.2.0.md` があれば SHA256 を追記して Notes に使う
   - `--publish` で `--draft=false --latest` を実行し、**stable** として公開
     （draft は配信対象外、pre-release はベータ用フィードのみへ配信。
     公開前に必須アセットの有無も確認し、公開後に更新フィードの生成を要求する）

   実行内容だけ確認したい場合は `--dry-run` を使う。

   手動で行う場合: タグ `v0.2.0` をpushし、Release名 `Awake v0.2.0`、Notesに
   変更点（**英語**）とSHA256を記載。添付は zip と `appcast.xml` が必須、
   `.dmg` と `.sha256` も推奨（手動ダウンロード用）。
5. 動作確認: Sparkle 導入版（0.2.0 以降）を入れた確認用Macで
   設定 > Software Updates > Check Now → 更新が見つかる → Install で
   置き換えと再起動が完了することを確認する。初回の Sparkle 導入版
   (0.2.0) から次版への更新が最初の実地テストになる。

## ブランチの運用

- `main` は正式版として配布する内容を保持する。
- `develop` は次の正式版に向けた開発とベータ版の配布に使う。
- 正式版の修正は `develop` にも取り込み、開発中の機能を保持する。
- `0.5.1` は `0.5.0` に更新フィードの分離とベータ受信設定を加えた移行用の正式版。
- 正式版を出すときは、`develop` を `main` にマージして push してから
  `scripts/release.sh X.Y.Z` を実行する（`release.sh` は HEAD と `origin/main` の一致を確認する）。
- `dist/` に同じ版数の古い ZIP・DMG・SHA256 が残っている場合は、`--skip-build` を使わない。
  ベータ期間中に作った成果物をそのまま正式版として添付しないため。

## ベータ版の配布

安定版と同じ署名・パッケージ手順で、GitHub のプレリリースとして配布する。
英語のノートを `dist/release-notes-v0.6.0-beta.1.md` に用意し、次を実行する。

```sh
scripts/release.sh 0.6.0-beta.1            # ビルド→タグ→draft prerelease 作成
scripts/release.sh --publish 0.6.0-beta.1  # 確認済み draft をプレリリースとして公開
```

- ZIP・DMG・SHA256 のファイル名とタグには `0.6.0-beta.1` を使う。
- `CFBundleShortVersionString` は `0.6.0`、`CFBundleVersion` は Apple の
  ベータ表記 `0.6.0b1` とする。ベータ番号は 1〜255 で、同じ版の次のベータでは
  番号を増やす。Sparkle は対応する安定版 `0.6.0` をベータより新しい版として扱う。
- ベータ版はクリーンな作業ツリーと `origin/develop` に一致する HEAD から作成する。
- 公開時は `--prerelease=true --latest=false` とし、安定版の `releases/latest`
  を置き換えない。既存の draft を再利用する場合も公開時にこの指定を適用する。
- 利用者は「設定 → 一般 → ベータ版を受け取る」（初期値オフ）でベータ版の
  アプリ内更新を選択できる。ベータ用フィードにも安定版を含めるため、対応する
  安定版の公開後はベータ版からも更新できる。オフにしてもダウングレードは行わない。
  手動でのダウンロード・インストールも可能。
- ベータのタグを安定版へ転用しない。安定版は `scripts/release.sh 0.6.0` で
  新しくビルド・作成・公開する。

## 更新フィードの生成・配信

`.github/workflows/update-feeds.yml` が公開済みリリースの `appcast.xml` を集約し、
専用の `update-feeds` ブランチへ `stable.xml` と `beta.xml` を1つのコミットで配信する。
GitHub Pages や追加の署名鍵は不要。既存の EdDSA 署名・ダウンロード先・macOS の
動作要件・リリースノートを保持する。未公開の draft は含めず、不正な版数や署名の
ない enclosure、必要な appcast の欠落があれば配信を中止する。

- 安定版: `https://raw.githubusercontent.com/PMGWork/awake/update-feeds/stable.xml`
- ベータ版と安定版: `https://raw.githubusercontent.com/PMGWork/awake/update-feeds/beta.xml`

ワークフローはリリースの公開・編集・削除時に実行する。初回はこのワークフローの
`main` へのマージでも実行し、既存の公開済みリリースからフィードを生成する。
`release.sh --publish` も明示的にワークフローを起動するため、`GITHUB_TOKEN` で
公開した場合にも対応する。実行には Actions の利用とワークフローの `contents: write`
権限が必要。公開後は Actions の **Publish update feeds** の成功を確認する。
GitHub のキャッシュにより、フィードの反映に少し時間がかかる場合がある。

新しいアプリを配布する前に、上記の2つの URL が取得できることを確認する。
既存のアプリは引き続き `releases/latest/download/appcast.xml` を使うため、
各リリースへの `appcast.xml` 添付も維持する。

生成失敗時や手動で再生成する場合:

```sh
gh workflow run update-feeds.yml --ref main --repo PMGWork/awake
```

ワークフローの生成処理は `scripts/generate-update-feeds.py`。ローカルで内容だけ
確認する場合は `python3 scripts/generate-update-feeds.py --repository PMGWork/awake`
を実行し、`dist/update-feeds/` の XML を確認する（ブランチへの配信は行わない）。

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

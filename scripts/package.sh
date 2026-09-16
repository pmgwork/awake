#!/bin/sh
# Build a distributable ZIP (+ optional DMG) without a paid Apple Developer
# account. No notarization: end users Gatekeeper-bypass once (see docs).
#
# Also generates the Sparkle appcast (dist/appcast.xml) that the in-app updater
# reads from GitHub Releases. The EdDSA private key lives in the login Keychain
# (create it once with dist/sparkle-tools/bin/generate_keys).
#
# Usage:
#   scripts/package.sh [version]
#   e.g. scripts/package.sh 0.2.0
# Output: dist/Awake-<version>.zip (+ .dmg when hdiutil available),
#         dist/Awake-<version>.sha256, dist/appcast.xml
set -eu

VERSION="${1:-0.2.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="awake.app"
DMG_NAME="Awake-${VERSION}.dmg"
ZIP_NAME="Awake-${VERSION}.zip"

# Toolchain: use DEVELOPER_DIR when already set, otherwise the standard Xcode
# install, falling back to the active developer directory. Release builds are
# made with Xcode 27 / the macOS 27 SDK so the app opts into the macOS 26/27
# behavior and appearance changes.
#
# The generic destination keeps Release universal (arm64 + x86_64); a plain
# `platform=macOS` destination silently builds only for the host architecture.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
export DEVELOPER_DIR

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME" "$DIST_DIR/$ZIP_NAME"

echo "==> Toolchain: $(xcodebuild -version | tr '\n' ' ')"
echo "==> Building Release (MARKETING_VERSION=$VERSION)..."
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$PROJECT_DIR/awake.xcodeproj" \
  -scheme awake \
  -configuration Release \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DIST_DIR/DerivedData" \
  build

BUILT_APP="$DIST_DIR/DerivedData/Build/Products/Release/$APP_NAME"
if [ ! -d "$BUILT_APP" ]; then
  echo "Build output not found: $BUILT_APP" >&2
  exit 1
fi

echo "==> Architectures: $(lipo -archs "$BUILT_APP/Contents/MacOS/awake")"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$BUILT_APP" || {
  echo "warning: codesign verify failed (ad-hoc / Apple Development build is expected without a paid account)" >&2
}
codesign -dv "$BUILT_APP" 2>&1 | head -n 8 || true

# Sparkle installs the app straight from this archive, so it is created with
# ditto (Finder's Compress equivalent), which preserves symlinks and bundle
# metadata, and the extracted copy is verified before anything is published.
echo "==> Creating ZIP..."
rm -rf "$DIST_DIR/stage" && mkdir -p "$DIST_DIR/stage"
ditto "$BUILT_APP" "$DIST_DIR/stage/Awake.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$DIST_DIR/stage/Awake.app" "$DIST_DIR/$ZIP_NAME"

echo "==> Verifying the extracted app..."
rm -rf "$DIST_DIR/stage/verify" && mkdir -p "$DIST_DIR/stage/verify"
ditto -x -k "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/stage/verify"
codesign --verify --deep --strict "$DIST_DIR/stage/verify/Awake.app" || {
  echo "error: signature verification failed for the app inside $ZIP_NAME" >&2
  exit 1
}
rm -rf "$DIST_DIR/stage"

# The DMG opens as a drag-to-Applications window: Awake.app on the left, an
# Applications shortcut on the right, at a fixed size. The volume name is
# stable so the layout is the same for every release.
DMG_VOLUME_NAME="Awake"
DMG_STAGE="$DIST_DIR/dmg"
DMG_RW="$DIST_DIR/Awake-$VERSION-rw.sparsebundle"
DMG_MOUNT_DIR="$DIST_DIR/dmg-mount/AwakeDMGBuild"

cleanup_dmg() {
  diskutil eject "$DMG_MOUNT_DIR" >/dev/null 2>&1 || true
  rm -rf "$DMG_STAGE" "$DMG_RW" "$DIST_DIR/dmg-mount"
}

if command -v diskutil >/dev/null 2>&1; then
  echo "==> Creating DMG..."
  trap cleanup_dmg EXIT
  cleanup_dmg
  mkdir -p "$DMG_STAGE"
  cp -R "$BUILT_APP" "$DMG_STAGE/Awake.app"
  ln -s /Applications "$DMG_STAGE/Applications"

  # A writable sparse bundle is created first so Finder can record the window
  # and icon positions in .DS_Store, then it is compressed to the final image.
  diskutil image create from "$DMG_STAGE" "$DMG_RW" --format UDSB \
    --volumeName "$DMG_VOLUME_NAME" >/dev/null
  mkdir -p "$DMG_MOUNT_DIR"
  diskutil image attach "$DMG_RW" --nobrowse \
    --mountPoint "$DMG_MOUNT_DIR" >/dev/null

  # Requires a logged-in Finder session; without one the DMG is still usable,
  # just without the arranged icons.
  if ! osascript <<'APPLESCRIPT'
tell application "Finder"
	tell disk "AwakeDMGBuild"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 140, 840, 540}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 128
		set position of item "Awake.app" of container window to {150, 180}
		set position of item "Applications" of container window to {490, 180}
		update without registering applications
		delay 1
		close
	end tell
end tell
APPLESCRIPT
  then
    echo "warning: could not apply the Finder layout (no GUI session?); creating a plain DMG" >&2
  fi

  diskutil eject "$DMG_MOUNT_DIR" >/dev/null
  diskutil image create from "$DMG_RW" "$DIST_DIR/$DMG_NAME" --format UDZO >/dev/null
  cleanup_dmg
  trap - EXIT
else
  echo "==> diskutil not found, skipping DMG"
fi

echo "==> Checksums..."
(cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" ${DMG_NAME:+$DMG_NAME} 2>/dev/null | tee "Awake-${VERSION}.sha256")

# --- Sparkle appcast ---------------------------------------------------------
# The appcast is uploaded to the GitHub Release and must also be reachable at
# releases/latest/download/appcast.xml, which SUFeedURL points at. The tools
# are cached in dist/ so subsequent runs work offline.
SPARKLE_VERSION="2.10.0"
SPARKLE_DIR="$DIST_DIR/sparkle-tools"

if [ ! -x "$SPARKLE_DIR/bin/generate_appcast" ]; then
  echo "==> Downloading Sparkle $SPARKLE_VERSION tools..."
  mkdir -p "$SPARKLE_DIR"
  curl -sSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o "$SPARKLE_DIR/sparkle.tar.xz"
  tar -xJf "$SPARKLE_DIR/sparkle.tar.xz" -C "$SPARKLE_DIR"
  rm -f "$SPARKLE_DIR/sparkle.tar.xz"
fi

if ! "$SPARKLE_DIR/bin/generate_keys" -p >/dev/null 2>&1; then
  echo "error: Sparkle signing key not found in the login Keychain." >&2
  echo "       Run '$SPARKLE_DIR/bin/generate_keys' once and keep the key safe." >&2
  exit 1
fi

echo "==> Generating appcast.xml..."
UPDATES_DIR="$DIST_DIR/updates"
rm -rf "$UPDATES_DIR" && mkdir -p "$UPDATES_DIR"
cp "$DIST_DIR/$ZIP_NAME" "$UPDATES_DIR/"
# Release notes are matched to the archive by file name.
if [ -f "$DIST_DIR/release-notes-v$VERSION.md" ]; then
  cp "$DIST_DIR/release-notes-v$VERSION.md" "$UPDATES_DIR/Awake-$VERSION.md"
fi
"$SPARKLE_DIR/bin/generate_appcast" \
  --download-url-prefix "https://github.com/PMGWork/awake/releases/download/v$VERSION/" \
  --embed-release-notes \
  --link "https://github.com/PMGWork/awake" \
  -o "$DIST_DIR/appcast.xml" \
  "$UPDATES_DIR"
rm -rf "$UPDATES_DIR"

# An unsigned feed would be rejected by every Sparkle-enabled install.
if ! grep -q 'sparkle:edSignature=' "$DIST_DIR/appcast.xml"; then
  echo "error: appcast.xml has no EdDSA signature." >&2
  echo "       Check SUPublicEDKey in awake/Info.plist and the Keychain key." >&2
  exit 1
fi

echo "Done: $DIST_DIR/$ZIP_NAME"
echo "      $DIST_DIR/appcast.xml (attach both to the v$VERSION release)"

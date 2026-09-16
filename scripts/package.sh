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
#   e.g. scripts/package.sh 0.1.2
# Output: dist/Awake-<version>.zip (+ .dmg when hdiutil available),
#         dist/Awake-<version>.sha256, dist/appcast.xml
set -eu

VERSION="${1:-0.1.2}"
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

echo "==> Creating ZIP..."
rm -rf "$DIST_DIR/stage" && mkdir -p "$DIST_DIR/stage"
cp -R "$BUILT_APP" "$DIST_DIR/stage/Awake.app"
(cd "$DIST_DIR/stage" && zip -qr -y "$DIST_DIR/$ZIP_NAME" "Awake.app")
rm -rf "$DIST_DIR/stage"

if command -v hdiutil >/dev/null 2>&1; then
  echo "==> Creating DMG..."
  rm -rf "$DIST_DIR/dmg" && mkdir -p "$DIST_DIR/dmg"
  cp -R "$BUILT_APP" "$DIST_DIR/dmg/Awake.app"
  hdiutil create -volname "Awake $VERSION" -srcfolder "$DIST_DIR/dmg" \
    -ov -format UDZO "$DIST_DIR/$DMG_NAME"
  rm -rf "$DIST_DIR/dmg"
else
  echo "==> hdiutil not found, skipping DMG"
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

echo "Done: $DIST_DIR/$ZIP_NAME"
echo "      $DIST_DIR/appcast.xml (attach both to the v$VERSION release)"

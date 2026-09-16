#!/bin/sh
# Update the Homebrew cask in PMGWork/homebrew-tap for a released version.
#
# Usage:
#   scripts/update-cask.sh <version>
#   e.g. scripts/update-cask.sh 0.1.3
#
# Reads Awake-<version>.sha256 from the GitHub Release and writes Casks/awake.rb
# through the GitHub API, so no local clone of the tap is needed.
set -eu

VERSION="${1:?usage: scripts/update-cask.sh <version>}"
REPO="PMGWork/awake"
TAP_REPO="PMGWork/homebrew-tap"
CASK_PATH="Casks/awake.rb"

echo "==> Fetching SHA256 for Awake-$VERSION.zip..."
SHA=$(curl -sSL \
  "https://github.com/$REPO/releases/download/v$VERSION/Awake-$VERSION.sha256" \
  | awk -v name="Awake-$VERSION.zip" '$2 == name { print $1 }')
if [ -z "$SHA" ]; then
  echo "error: could not read the SHA256 for Awake-$VERSION.zip." >&2
  echo "       Is v$VERSION released with the .sha256 asset attached?" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/awake.rb" <<EOF
cask "awake" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Awake-#{version}.zip"
  name "Awake"
  desc "Keeps your Mac awake while AI coding agents are running"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Awake.app"

  zap trash: [
    "~/Library/Application Support/Awake",
    "~/Library/Preferences/pmgwork.awake.plist",
  ]
end
EOF

CONTENT=$(base64 < "$WORK_DIR/awake.rb" | tr -d '\n')
EXISTING_SHA=""
if gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq .sha > "$WORK_DIR/existing-sha" 2>/dev/null; then
  EXISTING_SHA=$(tr -d '\n' < "$WORK_DIR/existing-sha")
fi

if [ -n "$EXISTING_SHA" ]; then
  ACTION="updated"
  # shellcheck disable=SC2086
  gh api --method PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
    -f message="awake $VERSION" \
    -f content="$CONTENT" \
    -f sha="$EXISTING_SHA" >/dev/null
else
  ACTION="created"
  gh api --method PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
    -f message="awake $VERSION" \
    -f content="$CONTENT" >/dev/null
fi

echo "==> Cask $ACTION: Awake $VERSION"
echo "    Install: brew install --cask pmgwork/tap/awake"

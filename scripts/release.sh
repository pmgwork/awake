#!/bin/sh
# One-command GitHub Release for Awake (wraps scripts/package.sh).
#
# Automates the manual steps in docs/DISTRIBUTION.md:
#   1. verify the working tree is clean and HEAD matches origin/main
#   2. build the ZIP/DMG and the Sparkle appcast via scripts/package.sh
#   3. create and push the annotated tag v<version>
#   4. create a draft GitHub Release with the artifacts attached
#
# The release stays a draft on purpose: SUFeedURL resolves through
# releases/latest, so users see nothing until the draft is published with
# --publish, which is also when the new appcast goes live.
#
# Usage:
#   scripts/release.sh <version>              build, tag, and draft a release
#   scripts/release.sh --publish <version>    publish the existing draft release
#   scripts/release.sh --skip-build <version> reuse dist/ artifacts as-is
#   scripts/release.sh --dry-run <version>    print the plan without changing anything
#
# The version is the marketing version (e.g. 0.3.0); the tag becomes v0.3.0.
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"

MODE="create"
SKIP_BUILD=0
DRY_RUN=0
VERSION=""

usage() {
    cat <<'EOF'
Usage:
  scripts/release.sh <version>              build, tag, and draft a release
  scripts/release.sh --publish <version>    publish the existing draft release
  scripts/release.sh --skip-build <version> reuse dist/ artifacts as-is
  scripts/release.sh --dry-run <version>    print the plan without changing anything

The version is the marketing version (e.g. 0.3.0); the tag becomes v0.3.0.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

run() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --publish)    MODE="publish" ;;
        --skip-build) SKIP_BUILD=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           usage >&2; die "unknown option: $1" ;;
        *)            VERSION="$1" ;;
    esac
    shift
done

[ -n "$VERSION" ] || { usage >&2; exit 1; }
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "version must look like \"0.3.0\" (got: $VERSION)"

TAG="v$VERSION"
NOTES="$DIST_DIR/release-notes-$TAG.md"
ZIP="$DIST_DIR/Awake-$VERSION.zip"
APPCAST="$DIST_DIR/appcast.xml"
DMG="$DIST_DIR/Awake-$VERSION.dmg"
SHA="$DIST_DIR/Awake-$VERSION.sha256"

cd "$PROJECT_DIR"

# --- Tooling / repository ----------------------------------------------------
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is not installed: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login' once."
git remote get-url origin >/dev/null 2>&1 || die "no \"origin\" remote is configured."

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
    || die "could not determine the GitHub repository for this checkout."

release_exists() {
    gh api "repos/$REPO/releases/tags/$TAG" >/dev/null 2>&1
}

release_is_draft() {
    [ "$(gh api "repos/$REPO/releases/tags/$TAG" --jq '.draft' 2>/dev/null || echo false)" = "true" ]
}

# --- Publish mode ------------------------------------------------------------
if [ "$MODE" = "publish" ]; then
    release_exists || die "no GitHub Release for $TAG; run scripts/release.sh $VERSION first."
    release_is_draft || die "$TAG is already published."

    for required in "Awake-$VERSION.zip" "appcast.xml"; do
        gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[].name' \
            | grep -qx "$required" \
            || die "draft $TAG has no $required asset; re-run scripts/release.sh $VERSION."
    done

    run gh release edit "$TAG" --draft=false --latest
    if [ "$DRY_RUN" = 1 ]; then
        echo "Dry run finished; nothing was changed."
    else
        echo "Published $TAG: https://github.com/$REPO/releases/tag/$TAG"
    fi
    exit 0
fi

# --- Preconditions (create mode) --------------------------------------------
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    die "the working tree has uncommitted changes; commit them first."
fi

git fetch origin --quiet --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    die "HEAD is not origin/main; pull or merge first so the tag lands on the released commit."
fi

TAG_TARGET="$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || true)"
if [ -n "$TAG_TARGET" ] && [ "$TAG_TARGET" != "$(git rev-parse HEAD)" ]; then
    die "tag $TAG exists and does not point at HEAD."
fi

if release_exists; then
    release_is_draft || die "$TAG is already published; bump the version instead of reusing it."
    echo "==> Draft release $TAG already exists; its assets will be refreshed."
fi

[ -f "$NOTES" ] || echo "warning: $NOTES not found; the Sparkle update dialog will have no embedded notes." >&2

# --- Build -------------------------------------------------------------------
if [ "$SKIP_BUILD" = 1 ]; then
    echo "==> Skipping scripts/package.sh (--skip-build)."
else
    run scripts/package.sh "$VERSION"
fi

for required in "$ZIP" "$APPCAST"; do
    [ -f "$required" ] || die "$required not found; run scripts/package.sh $VERSION first."
done
[ -f "$DMG" ] || echo "warning: $DMG not found; the release will have no drag-and-drop DMG." >&2
[ -f "$SHA" ] || echo "warning: $SHA not found; the release will have no checksums." >&2

if ! grep -q "sparkle:version=\"$VERSION\"" "$APPCAST" \
    && ! grep -q "sparkle:shortVersionString=\"$VERSION\"" "$APPCAST"; then
    echo "warning: $APPCAST does not mention $VERSION; it may be stale." >&2
fi

# --- Tag ---------------------------------------------------------------------
if [ -n "$TAG_TARGET" ]; then
    echo "==> Reusing existing tag $TAG."
else
    echo "==> Creating and pushing tag $TAG..."
    run git tag -a "$TAG" -m "Awake $TAG"
    run git push origin "$TAG"
fi

# --- Release -----------------------------------------------------------------
set -- "$TAG" "$ZIP" "$APPCAST"
if [ -f "$DMG" ]; then set -- "$@" "$DMG"; fi
if [ -f "$SHA" ]; then set -- "$@" "$SHA"; fi

if release_exists; then
    echo "==> Uploading assets to the existing draft..."
    run gh release upload "$@" --clobber
else
    echo "==> Creating draft release $TAG..."
    if [ -f "$NOTES" ]; then
        NOTES_FILE="$NOTES"
        if [ -f "$SHA" ]; then
            NOTES_FILE="$DIST_DIR/.release-notes-with-checksums-$TAG.md"
            { cat "$NOTES"; printf '\n## SHA256\n\n```\n'; cat "$SHA"; printf '```\n'; } > "$NOTES_FILE"
        fi
        run gh release create "$@" --title "Awake $TAG" --notes-file "$NOTES_FILE" --draft --verify-tag
    else
        run gh release create "$@" --title "Awake $TAG" --generate-notes --draft --verify-tag
    fi
fi

echo ""
if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run finished; nothing was changed."
else
    echo "Draft release ready: https://github.com/$REPO/releases/tag/$TAG"
    echo "Check the assets and notes, then publish with:"
    echo "    scripts/release.sh --publish $VERSION"
fi

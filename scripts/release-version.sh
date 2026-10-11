#!/bin/sh
# Shared version validation for packaging and GitHub Releases.
# Sets MARKETING_VERSION, BUILD_VERSION, and IS_PRERELEASE from VERSION.

IS_PRERELEASE=false
if printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    MARKETING_VERSION="$VERSION"
    BUILD_VERSION="$VERSION"
elif printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[1-9][0-9]{0,2}$'; then
    MARKETING_VERSION="${VERSION%-beta.*}"
    BETA_NUMBER="${VERSION##*-beta.}"
    if [ "$BETA_NUMBER" -gt 255 ]; then
        echo 'error: beta number must be between 1 and 255.' >&2
        exit 1
    fi
    # CFBundleShortVersionString stays numeric. CFBundleVersion uses Apple's
    # beta suffix, which Sparkle orders before the matching stable version.
    BUILD_VERSION="${MARKETING_VERSION}b${BETA_NUMBER}"
    IS_PRERELEASE=true
else
    echo 'error: version must look like "0.6.0" or "0.6.0-beta.1" (beta number 1–255).' >&2
    exit 1
fi

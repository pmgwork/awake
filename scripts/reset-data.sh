#!/bin/sh
# Reset Awake's user-level state after integrations have been unlinked in the app.
set -eu

pkill -f '/[Aa]wake.app/Contents/MacOS/[Aa]wake' 2>/dev/null || true
defaults delete pmgwork.awake 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/Awake"
rm -rf "$HOME/Library/Caches/pmgwork.awake"
rm -rf "$HOME/Library/Saved Application State/pmgwork.awake.savedState"
rm -rf "$HOME/Library/HTTPStorages/pmgwork.awake"
rm -rf "$HOME/Library/WebKit/pmgwork.awake"
tccutil reset Notifications pmgwork.awake 2>/dev/null || true

echo "Awake user data was removed."

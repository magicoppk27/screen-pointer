#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in "build/Screen Pointer.app".
# Usage: scripts/build-app.sh [debug|release]
# Set SIGN_IDENTITY to a Developer ID / Apple Development identity to keep
# macOS permissions (Input Monitoring) across rebuilds; defaults to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ScreenPointer"

APP="build/Screen Pointer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenPointer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"

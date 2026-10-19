#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in "build/Screen Pointer.app".
# Usage: scripts/build-app.sh [debug|release]
# Signs with the stable self-signed identity from scripts/setup-signing.sh (created on
# first use) so macOS keeps the Input Monitoring permission across rebuilds.
# Override with SIGN_IDENTITY="<name or SHA-1>", or SIGN_IDENTITY=- for ad-hoc.
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
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    IDENTITY="$(scripts/setup-signing.sh)"
    codesign --force --keychain "$PWD/.signing/signing.keychain-db" --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP"

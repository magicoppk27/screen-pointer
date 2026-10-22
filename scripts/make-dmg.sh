#!/usr/bin/env bash
# Builds a shareable installer: dist/ScreenPointer-<version>-arm64.dmg
# containing the app, an Applications shortcut (drag to install) and install instructions.
#
# Signing: by default the app is signed with the local self-signed identity (see
# scripts/setup-signing.sh). It's the same identity for every release, so recipients keep
# their Input Monitoring grant across updates. It is NOT notarized, so recipients must
# approve it once in System Settings → Privacy & Security ("Open Anyway").
#
# With an Apple Developer ID (paid Apple Developer Program) you can notarize instead:
#   xcrun notarytool store-credentials screenpointer-notary   # one time
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=screenpointer-notary scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
NAME="Screen Pointer"
APP="build/$NAME.app"
DMG="dist/ScreenPointer-$VERSION-arm64.dmg"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    # Notarization needs the hardened runtime and a secure timestamp.
    SIGN_IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity}" \
        scripts/build-app.sh release
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    scripts/build-app.sh release
fi

if [[ "$(lipo -archs "$APP/Contents/MacOS/ScreenPointer")" != "arm64" ]]; then
    echo "error: expected an arm64-only binary" >&2
    exit 1
fi

STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to Install.txt" <<EOF
Screen Pointer $VERSION
For Macs with Apple silicon (M1 or later), macOS 14 Sonoma or newer.

INSTALL
1. Drag "Screen Pointer" onto the Applications folder in this window.
2. Eject this disk image.
3. Open Screen Pointer from Applications (or Spotlight).

FIRST LAUNCH — "Screen Pointer" Not Opened / "Apple could not verify…"
This app isn't distributed through the App Store, so macOS asks you to approve it once:
1. Click "Done" (not "Move to Trash") in the warning.
2. Open System Settings → Privacy & Security.
3. Scroll down to the message about "Screen Pointer" and click "Open Anyway".
4. Confirm with your password or Touch ID, then click "Open Anyway" again.
You only need to do this once.

Alternative (Terminal):
  xattr -dr com.apple.quarantine "/Applications/Screen Pointer.app"

USING IT
Screen Pointer lives in the menu bar (cursor icon). There's no Dock icon.
  ⌃⌥C  Cursor highlight on/off
  ⌃⌥K  Show keystrokes on/off
  ⌃⌥D  Draw on screen (Esc or right-click to exit)
Settings… in the menu bar icon has colors, sizes and opacity.

SHOW KEYSTROKES needs "Input Monitoring":
System Settings → Privacy & Security → Input Monitoring → turn on Screen Pointer,
then turn Show Keystrokes on again. Nothing you type is stored or sent anywhere.

UNINSTALL
Quit it from the menu bar icon and drag it from Applications to the Trash.
EOF

mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$(dirname "$STAGE")"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

(cd dist && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"

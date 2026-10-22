#!/bin/bash
# Installs (or updates) the latest Screen Pointer release from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/magicoppk27/screen-pointer/main/scripts/web-install.sh | bash
set -euo pipefail

REPO="magicoppk27/screen-pointer"
BASE="https://github.com/$REPO/releases/latest/download"
NAME="Screen Pointer.app"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -m)" == "arm64" ]] || fail "Screen Pointer needs a Mac with Apple silicon (M1 or later)."
(( $(sw_vers -productVersion | cut -d. -f1) >= 14 )) || fail "Screen Pointer needs macOS 14 Sonoma or later."

DEST_DIR="/Applications"
[[ -w "$DEST_DIR" ]] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
DEST="$DEST_DIR/$NAME"

TMP="$(mktemp -d)"
MNT="$TMP/mnt"
cleanup() { hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading Screen Pointer…"
curl -fL --progress-bar -o "$TMP/ScreenPointer.dmg" "$BASE/ScreenPointer-arm64.dmg"
EXPECTED="$(curl -fsSL "$BASE/ScreenPointer-arm64.dmg.sha256" | awk '{print $1}')"
ACTUAL="$(shasum -a 256 "$TMP/ScreenPointer.dmg" | awk '{print $1}')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] || fail "checksum mismatch — download corrupted or tampered with; nothing was installed."

mkdir -p "$MNT"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$TMP/ScreenPointer.dmg"
[[ -d "$MNT/$NAME" ]] || fail "the disk image doesn't contain $NAME."

pkill -x ScreenPointer 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$MNT/$NAME" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
codesign --verify --strict "$DEST" || fail "the installed app's signature is invalid."

VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
open "$DEST"
echo "Installed Screen Pointer $VERSION in $DEST_DIR. Look for the cursor icon in the menu bar."

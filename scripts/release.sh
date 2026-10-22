#!/usr/bin/env bash
# Builds the DMG and publishes it as GitHub release v<version>, with version-less asset names
# so .../releases/latest/download/ScreenPointer-arm64.dmg always points at the newest one
# (used by scripts/web-install.sh). Bump CFBundleShortVersionString in Resources/Info.plist first.
set -euo pipefail
cd "$(dirname "$0")/.."

GH="${GH:-$(command -v gh || echo "$HOME/.local/bin/gh")}"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"

[[ -z "$(git status --porcelain)" ]] || { echo "error: commit your changes first" >&2; exit 1; }
if "$GH" release view "$TAG" >/dev/null 2>&1; then
    echo "error: release $TAG already exists — bump the version in Resources/Info.plist" >&2
    exit 1
fi

scripts/make-dmg.sh
OUT="$(mktemp -d)"
cp "dist/ScreenPointer-$VERSION-arm64.dmg" "$OUT/ScreenPointer-arm64.dmg"
(cd "$OUT" && shasum -a 256 ScreenPointer-arm64.dmg > ScreenPointer-arm64.dmg.sha256)

git push origin HEAD
"$GH" release create "$TAG" "$OUT/ScreenPointer-arm64.dmg" "$OUT/ScreenPointer-arm64.dmg.sha256" \
    --title "Screen Pointer $VERSION" --target "$(git rev-parse HEAD)" \
    --notes "Install or update from Terminal (Apple silicon, macOS 14+):

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/magicoppk27/screen-pointer/main/scripts/web-install.sh | bash
\`\`\`

Or download **ScreenPointer-arm64.dmg** below and drag the app to Applications. It isn't notarized, so the first launch needs System Settings → Privacy & Security → **Open Anyway** (the Terminal install skips this)."
rm -rf "$OUT"

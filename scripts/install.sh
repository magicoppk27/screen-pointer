#!/usr/bin/env bash
# Builds a release bundle, installs it to /Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release
pkill -x ScreenPointer || true
DEST="/Applications/Screen Pointer.app"
rm -rf "$DEST"
ditto "build/Screen Pointer.app" "$DEST"
rm -rf "build/Screen Pointer.app"  # avoid a duplicate in Spotlight/Launchpad
open "$DEST"
echo "Installed $DEST"

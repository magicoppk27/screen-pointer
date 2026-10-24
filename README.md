# Screen Pointer

## Install (Apple silicon Mac, macOS 14+)

Paste this into Terminal. It downloads the latest release, checks its checksum, installs it to
Applications and opens it. Run it again any time to update.

```bash
curl -fsSL https://raw.githubusercontent.com/magicoppk27/screen-pointer/main/scripts/web-install.sh | bash
```

Or download `ScreenPointer-arm64.dmg` from [Releases](https://github.com/magicoppk27/screen-pointer/releases/latest)
and drag the app to Applications. The DMG route needs a one-time **Open Anyway** in System
Settings → Privacy & Security, because the app isn't notarized.

A menu-bar macOS app (macOS 14+) for presentations and screen recordings, inspired by
ScreenCursor. It's a new implementation in Swift/SwiftUI and doesn't reuse any of
ScreenCursor's code.

## Features

| Feature | How | Default shortcut |
| --- | --- | --- |
| Cursor highlight | Click-through halo that follows the mouse, changes color on left/right click with a ripple, and fades when the mouse is idle | ⌃⌥C |
| Keystroke overlay | Listen-only `CGEventTap`; shortcuts appear as chips, plain typing merges into one line, everything fades after 2 s | ⌃⌥K |
| Draw on screen | Full-screen canvas on the screen under the mouse: pen, line, arrow, rectangle, ellipse, numbered markers, 8 colors, 3 widths, undo, clear, click-through | ⌃⌥D |
| Magnifier | Round lens that follows the cursor (ScreenCaptureKit). Tap to toggle, hold for a lens that shows only while held; ⌃⌥= / ⌃⌥− zoom 1.5–10× and Esc or X closes it while it's showing. Map a mouse button to ⌃⌥M for hold-to-magnify | ⌃⌥M |
| Turn off all | Switches every feature off at once (the app stays in the menu bar). Also in the menu | ⌃⌥X |

All shortcuts except Esc can be changed in **Settings → Shortcuts**: click one and press the
new keys. Global shortcuts must include ⌃, ⌥ or ⌘. Conflicts are rejected, and a ⚠ marks a
combo that another app already owns.

Exit drawing with Esc, a right-click, or the ✕ on the toolbar. Settings (colors, sizes,
opacity) are in the menu-bar icon → Settings… and are saved to UserDefaults.

## Requirements

- A Mac with Apple Silicon (M-series). The app is built for arm64 only.
- macOS 14 (Sonoma) or later.
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

## Build & install

```bash
git clone https://github.com/magicoppk27/screen-pointer.git
cd screen-pointer
scripts/install.sh
```

`scripts/install.sh` makes a release build, quits any running copy, installs it to
`/Applications/Screen Pointer.app` and launches it. The other scripts:

```bash
scripts/build-app.sh          # build only → build/Screen Pointer.app (pass "debug" for a debug build)
scripts/make-icon.sh          # regenerate Resources/AppIcon.{png,icns} from scripts/make-icon.swift
scripts/setup-signing.sh      # create/unlock the signing certificate (build-app.sh runs it for you)
scripts/make-dmg.sh           # shareable installer → dist/ScreenPointer-<version>-arm64.dmg
scripts/release.sh            # build the DMG and publish GitHub release v<version>
scripts/web-install.sh        # what the one-line Terminal installer runs
```

`swift build` by itself produces a bare executable. Use the scripts to get a real `.app`
bundle (`LSUIElement`, bundle ID, code signature), which macOS needs before it will grant permissions.

## Sharing with others

```bash
scripts/make-dmg.sh
```

This creates `dist/ScreenPointer-<version>-arm64.dmg` (plus a `.sha256` checksum). The disk
image contains the app, an Applications shortcut to drag it onto, and a "How to Install.txt"
for recipients. It works on Apple silicon Macs running macOS 14+.

The app isn't notarized (that needs a paid Apple Developer ID), so on first launch macOS
says it can't verify the app. Recipients approve it once in **System Settings → Privacy &
Security → Open Anyway**; the included instructions walk them through it. Releases are all
signed with the same certificate, so updating keeps their permissions. Bump
`CFBundleShortVersionString` in `Resources/Info.plist` before building a new release.

To publish a release, commit everything, bump the version, then run `scripts/release.sh`. It
uploads `ScreenPointer-arm64.dmg` and its `.sha256` under fixed names, so
`releases/latest/download/…`, and therefore the one-line installer, always gets the newest one.

## Permissions

- **Input Monitoring** is required for the keystroke overlay. The app asks the first time
  you turn the overlay on.
- **Screen Recording** is required for the magnifier, to see what's under the cursor. Nothing is
  recorded or saved. The lens leaves out Screen Pointer's own windows, so it doesn't magnify
  drawings or keystroke bubbles. macOS may ask to reopen the app after you grant it.
- The cursor highlight, drawing, and hotkeys need no permissions.
- Builds are signed with a stable self-signed certificate that `scripts/setup-signing.sh`
  creates on the first build, in `.signing/` (not in git). macOS therefore remembers the
  Input Monitoring and Screen Recording grants across rebuilds: grant them once per Mac. Back up `.signing/` if you
  want to reuse the same certificate on another Mac without granting it again. See
  [CLAUDE.md](CLAUDE.md) for details.

## Toolchain note

The Command Line Tools SDK declares SwiftUI's `@State` as a macro but doesn't ship its
plugin, so `@State` won't compile without full Xcode. The code keeps view state in
`ObservableObject`s instead.

## Layout

```
Sources/ScreenPointer/
  ScreenPointerApp.swift   App entry, menu-bar menu, AppDelegate
  AppSettings.swift        Persisted preferences
  CursorHighlight.swift    Mouse-following halo + click colors
  KeystrokeOverlay.swift   Event tap + keystroke HUD
  DrawMode.swift           Canvas window, tools, renderer, toolbar
  HotKeys.swift            Carbon global hotkeys (press + release, diff-based rebinding)
  Shortcuts.swift          Editable shortcuts: model, persistence, recorder
  Magnifier.swift          ScreenCaptureKit lens
  SettingsWindow.swift     Settings UI
  Support.swift            Overlay panel, color hex, permissions helpers
```

## Ideas for next steps

- Text tool and a highlighter or spotlight tool in draw mode
- Launch at login (`SMAppService.mainApp`)

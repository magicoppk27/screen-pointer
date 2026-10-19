# Screen Pointer

A menu-bar macOS app (macOS 14+) for presentations and screen recordings, inspired by
ScreenCursor. It's a new implementation in Swift/SwiftUI and doesn't reuse any of
ScreenCursor's code.

## Features

| Feature | How | Hotkey |
| --- | --- | --- |
| Cursor highlight | Click-through halo that follows the mouse, changes color on left/right click with a ripple, and fades when the mouse is idle | ⌃⌥C |
| Keystroke overlay | Listen-only `CGEventTap`; shortcuts appear as chips, plain typing merges into one line, everything fades after 2 s | ⌃⌥K |
| Draw on screen | Full-screen canvas on the screen under the mouse: pen, line, arrow, rectangle, ellipse, numbered markers, 8 colors, 3 widths, undo, clear, click-through | ⌃⌥D |

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
```

`swift build` by itself produces a bare executable. Use the scripts to get a real `.app`
bundle (`LSUIElement`, bundle ID, code signature), which macOS needs before it will grant permissions.

## Permissions

- **Input Monitoring** is required for the keystroke overlay. The app asks the first time
  you turn the overlay on.
- The cursor highlight, drawing, and hotkeys need no permissions.
- By default builds are ad-hoc signed, so macOS forgets the Input Monitoring grant after
  every rebuild. To keep it, sign with a stable self-signed certificate:
  `SIGN_IDENTITY="<certificate name>" scripts/install.sh`. [CLAUDE.md](CLAUDE.md) has
  the setup steps. The certificate stays outside git, in `.signing/`.

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
  HotKeys.swift            Carbon global hotkeys
  SettingsWindow.swift     Settings UI
  Support.swift            Overlay panel, color hex, permissions helpers
```

## Ideas for next steps

- Hotkeys you can rebind (e.g. with a shortcut recorder)
- Text tool and a highlighter or spotlight tool in draw mode
- Launch at login (`SMAppService.mainApp`)

# CLAUDE.md — Screen Pointer

Guidance for Claude Code sessions working on this repo. Screen Pointer is a macOS menu-bar
app (Swift/SwiftUI + AppKit) with a cursor highlight, keystroke overlay and on-screen
drawing. See [README.md](README.md) for features.

## "Clone my screen-pointer repo, build and install it"

```bash
git clone https://github.com/magicoppk27/screen-pointer.git ~/Documents/screen-pointer
cd ~/Documents/screen-pointer
xcode-select -p || xcode-select --install   # Command Line Tools are enough
scripts/install.sh
```

`scripts/install.sh` does a release build (`scripts/build-app.sh release`), quits a running
copy (`pkill -x ScreenPointer`), copies the bundle to `/Applications/Screen Pointer.app`
with `ditto`, deletes `build/Screen Pointer.app` (so Spotlight/Launchpad don't show two copies)
and opens the installed app. Check success with `pgrep -lf ScreenPointer`. The path should be
under `/Applications`.

Signing is automatic. On the first build `scripts/setup-signing.sh` creates a stable self-signed
identity in `.signing/` (gitignored), and every build is signed with it. On a new Mac the
user grants Input Monitoring once after the first install, and it then survives rebuilds.

## Prerequisites

- **Apple Silicon (M-series) only.** Build for arm64 only. Never add Intel (`x86_64`) or
  universal builds, `--arch` flags, or `lipo` steps.
- macOS 14+ (`LSMinimumSystemVersion` 14.0, `platforms: [.macOS(.v14)]` in Package.swift).
- **Xcode Command Line Tools only.** Full Xcode is not installed or required. There is no
  `.xcodeproj`. The project is a Swift package (`swift-tools-version:5.10`, Swift 5 language
  mode) built with `swift build`, then wrapped into a `.app` by `scripts/build-app.sh`.
- Homebrew is **not** installed on the original Mac. Don't assume `brew`.

## Project facts

- Bundle ID: `local.screenpointer.ScreenPointer`. Executable: `ScreenPointer`. Display name:
  "Screen Pointer". `LSUIElement` = true (menu bar only, no Dock icon).
- `Resources/Info.plist` is copied into the bundle by hand. SwiftPM doesn't generate it. Edit
  it there.
- Icon: `scripts/make-icon.swift` draws it with CoreGraphics, and `scripts/make-icon.sh`
  produces `Resources/AppIcon.png` and `Resources/AppIcon.icns` (both committed). Rerun the
  script after changing the drawing.
- Settings persist in UserDefaults under the bundle ID.
- Hotkeys (Carbon `RegisterEventHotKey`, no permission needed) are **user-editable** in Settings →
  Shortcuts (`Shortcuts.swift`: the `ShortcutAction` enum, `ShortcutStore` persisted as JSON under
  the UserDefaults key `shortcuts`, storing only changed ones). Defaults: ⌃⌥C cursor highlight,
  ⌃⌥K keystrokes, ⌃⌥D draw mode, ⌃⌥M magnifier, ⌃⌥X turn off all features (`Features.turnOffAll()`:
  every overlay off, app keeps running), and, lens-only, ⌃⌥= / ⌃⌥- zoom and bare X to close. Esc
  always closes the lens and isn't editable.
  - Global actions must include ⌃/⌥/⌘. Lens-only ones may be bare keys, because they're
    registered only while the lens shows (they're swallowed system-wide during that time, which
    the user accepted).
  - Recording uses a local keyDown monitor and calls `HotKeyCenter.suspend()` first, so the
    current combo is captured instead of fired. Esc cancels. Conflicts are rejected.
  - `HotKeyCenter.rebind()` is diff-based: unchanged registrations are kept. That matters,
    because opening the lens on a held ⌃⌥M rebinds, and re-registering ⌃⌥M would lose its release
    event (breaking hold-to-magnify).
  - Combos another app owns fail to register and show ⚠ (`ShortcutStore.unavailable`).
  - Carbon hot key IDs: 1–6, 8 and 9 for the actions, 7 for the fixed Esc.
  - Carbon also defines `EventModifiers`, so write `SwiftUI.EventModifiers` in files that
    import Carbon.
  - A tap of the magnifier key toggles the lens. Holding it for 0.35 s or more makes it
    momentary (`kEventHotKeyReleased`). The lens ring has no shadow, at the user's request. Open, close and hotkey
  presses are logged with NSLog (`Screen Pointer: magnifier …`) for diagnosis. If another app holds a combo, registration fails and the app
  logs `Screen Pointer: hotkey N is already taken`.

## Magnifier

- `Magnifier.swift`: ScreenCaptureKit `SCStream` of the whole display under the mouse at native
  pixels, 60 fps. The IOSurface goes into a `CALayer`, and `contentsRect` crops it around the
  cursor. On macOS `contentsRect` y=0 is the bottom of the image (verified), the same as Cocoa
  screen coordinates. The stream restarts when the mouse moves to another display.
- The filter excludes the whole app (`excludingApplications: [own pid]`) so the lens never
  magnifies itself. Side effect: drawings and keystroke bubbles aren't magnified. Excluding
  only the lens window was racy, because the window may not be in `SCShareableContent` yet.
- `showsCursor = false`, because the real cursor already sits at the lens centre.
- Verified working by the user on 2026-10-22 (v0.2.0).

## Gotchas

- **`@State` doesn't compile with Command Line Tools.** The CLT SDK declares SwiftUI's
  `@State` (and `@Entry`, `@Animatable`) as macros but doesn't ship the `SwiftUIMacros` plugin:
  `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`. Don't use
  `@State`. Keep view state in an `ObservableObject` (`@Published`) and use `@ObservedObject`.
  `@ObservedObject`, `@Published`, `@Binding` and `@NSApplicationDelegateAdaptor` work.
- These linker warnings are harmless; ignore them:
  `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/...' not found`.
- The settings window is a plain AppKit `NSWindow` hosting SwiftUI
  (`SettingsWindowController`), because SwiftUI's `Settings` scene doesn't open reliably from a
  menu-bar-only app.
- The draw canvas window uses an almost-transparent background (alpha 0.01) on purpose.
  A fully clear window lets clicks through.
- `swift build` alone gives a bare binary that macOS won't grant permissions to. Always go
  through `scripts/build-app.sh` / `scripts/install.sh`.

## macOS permissions and code signing

- **Input Monitoring** (TCC service `ListenEvent`) is needed for the keystroke overlay
  (a listen-only `CGEventTap`, checked with `CGPreflightListenEventAccess`). Cursor highlight,
  drawing and hotkeys need no permissions. The app does **not** use Screen Recording,
  Accessibility or the Microphone.
- **Screen Recording** (`ScreenCapture`, `CGPreflightScreenCaptureAccess`) is needed for the
  magnifier. `CGRequestScreenCaptureAccess` shows the system prompt once. After that the app shows
  an alert linking to `Privacy_ScreenCapture`. macOS may require relaunching the app after the
  grant. The same stable-signing rules apply. Reset with
  `tccutil reset ScreenCapture local.screenpointer.ScreenPointer`.
- **Ad-hoc signing (`codesign --sign -`, no longer used here) makes macOS forget the permission after
  every rebuild.** TCC identifies ad-hoc apps by cdhash, which changes with every build, so the
  grant goes stale and the user gets stuck re-granting. Toggling the switch in System Settings
  doesn't replace a stale entry; delete it, or run
  `tccutil reset ListenEvent local.screenpointer.ScreenPointer`.
- **Fix (in place): every build is signed with a stable self-signed certificate.**
  `scripts/build-app.sh` calls `scripts/setup-signing.sh`, which:
  - on first run, creates `.signing/` (gitignored, mode 700) with a "Screen Pointer Local
    Signing" code-signing certificate (RSA 2048, 10 years) in its own keychain,
    `.signing/signing.keychain-db`. The keychain password is in `.signing/keychain-password`;
    the private key exists only inside that keychain.
  - adds that keychain to the user keychain search list (the original list is saved in
    `.signing/search-list-backup.txt`), unlocks it and prints the identity's SHA-1, which
    `codesign --keychain … --sign <sha1>` uses.
  - is idempotent. Later runs only re-add and unlock the keychain (it locks after a reboot).
- Override with `SIGN_IDENTITY="<name or sha1>" scripts/install.sh`, or `SIGN_IDENTITY=-` for
  ad-hoc (permissions will then be lost on every rebuild).
- Verify: `codesign -dr - "/Applications/Screen Pointer.app"` must show
  `identifier "local.screenpointer.ScreenPointer" and certificate leaf = H"…"`, not `cdhash H"…"`.
  The leaf hash must stay the same across rebuilds.
- **New Mac / new certificate:** a different certificate means a different requirement, so the
  old grant doesn't match. Install, then turn on Show Keystrokes and grant Input Monitoring once.
  If an older entry is stuck (switch on but the overlay still asks), run
  `tccutil reset ListenEvent local.screenpointer.ScreenPointer` and grant again. Toggling the
  switch in System Settings never replaces a stale entry.
- To diagnose permission loops, run `log show --last 5m --predicate 'process == "tccd"'` and look
  for `Failed to match existing code requirement`.
- To keep the *same* certificate on another Mac (no re-grant), copy `.signing/` into the clone
  before the first build. Back up `.signing/` separately; it is intentionally not on GitHub.
- If `security import` rejects the .p12 (e.g. OpenSSL 3 instead of the system LibreSSL is first
  on `PATH`), add `-legacy` to the `openssl pkcs12` call in `setup-signing.sh`.

## Releases and the one-line installer

- The repo is **public** (the user made it public on 2026-10-22 and is fine with that).
- `scripts/release.sh`: refuses to run with uncommitted changes or an existing tag. It runs
  `make-dmg.sh`, pushes, and creates GitHub release `v<CFBundleShortVersionString>` with the
  assets `ScreenPointer-arm64.dmg` and `ScreenPointer-arm64.dmg.sha256` (fixed names, so
  `releases/latest/download/…` always resolves). Bump the version (and `CFBundleVersion`) first.
- `scripts/web-install.sh` is what users run:
  `curl -fsSL https://raw.githubusercontent.com/magicoppk27/screen-pointer/main/scripts/web-install.sh | bash`.
  It checks arm64 and macOS 14+, downloads the latest DMG, verifies the SHA-256, installs to
  /Applications (or ~/Applications if it isn't writable), strips quarantine, verifies the
  signature and opens the app. Files downloaded with curl aren't quarantined, so there's no
  Gatekeeper "Open Anyway" step.

## Shareable installer

- `scripts/make-dmg.sh` produces `dist/ScreenPointer-<version>-arm64.dmg` (gitignored), with
  the app, an `/Applications` symlink and "How to Install.txt", plus a `.sha256` checksum. The
  version comes from `CFBundleShortVersionString` in `Resources/Info.plist`. The script fails
  if the binary isn't arm64-only.
- The default signature is the local self-signed identity, which is **not notarized**: `spctl`
  reports `rejected` for a downloaded (quarantined) copy, and that is expected. Recipients use
  System Settings → Privacy & Security → "Open Anyway" once (macOS 15+ removed the
  right-click → Open bypass). Always share DMGs built with the same `.signing/` certificate, so
  recipients keep their Input Monitoring grant across updates.
- An optional notarized path exists (`SIGN_IDENTITY="Developer ID Application: …"
  NOTARY_PROFILE=<notarytool profile>`), but it has never been run. The user has no Developer ID
  yet.

## Repo hygiene

- Never commit `.signing/`, keychains, `*.p12`/`*.pem`/`*.key`/`*.cer`, provisioning profiles,
  `.env*`, tokens, or build output (`.build/`, `build/`). `.gitignore` covers these, so keep it
  that way.
- Git author for this repo (local config, not global): Rodrigo Furtado <magicoppk@gmail.com>.
- Remote: `github.com/magicoppk27/screen-pointer` (private). The GitHub CLI is at `~/.local/bin/gh`.

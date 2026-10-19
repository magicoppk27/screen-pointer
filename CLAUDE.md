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

If a stable signing certificate is set up (see below), install with
`SIGN_IDENTITY="Screen Pointer Local Signing" scripts/install.sh` instead.

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
- Hotkeys (Carbon `RegisterEventHotKey`, no permission needed): ⌃⌥C cursor highlight, ⌃⌥K
  keystrokes, ⌃⌥D draw mode. If another app holds a combo, registration fails and the app
  logs `Screen Pointer: hotkey N is already taken`.

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
- **Ad-hoc signing (the default, `codesign --sign -`) makes macOS forget the permission after
  every rebuild.** TCC identifies ad-hoc apps by cdhash, which changes with every build, so the
  grant goes stale and the user gets stuck re-granting. Toggling the switch in System Settings
  doesn't replace a stale entry; delete it, or run
  `tccutil reset ListenEvent local.screenpointer.ScreenPointer`.
- **Fix: sign with a stable self-signed certificate kept outside git** in `.signing/` (which is
  gitignored). This is not set up for this project yet. One-time setup from the repo root:

  ```bash
  mkdir -p .signing && cd .signing
  PW="$(openssl rand -hex 16)"; printf %s "$PW" > keychain-password; chmod 600 keychain-password
  cat > cert.cnf <<'EOF'
  [req]
  distinguished_name = dn
  x509_extensions = ext
  prompt = no
  [dn]
  CN = Screen Pointer Local Signing
  [ext]
  basicConstraints = critical,CA:false
  keyUsage = critical,digitalSignature
  extendedKeyUsage = critical,codeSigning
  EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
  openssl pkcs12 -export -inkey key.pem -in cert.pem -out signing.p12 -passout pass:"$PW"
  KC="$PWD/signing.keychain-db"
  security create-keychain -p "$PW" "$KC"
  security set-keychain-settings "$KC"            # no auto-lock timeout
  security unlock-keychain -p "$PW" "$KC"
  security import signing.p12 -k "$KC" -P "$PW" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC"
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
  rm key.pem signing.p12
  cd .. && SIGN_IDENTITY="Screen Pointer Local Signing" scripts/install.sh
  ```

  - If `openssl pkcs12` fails to import (OpenSSL 3 instead of the system LibreSSL), add `-legacy`.
  - Verify with `codesign -dr - "/Applications/Screen Pointer.app"`. It must show
    `certificate leaf = H"…"`, not `cdhash H"…"`.
  - After switching from ad-hoc to the certificate, reset the old grant once
    (`tccutil reset ListenEvent local.screenpointer.ScreenPointer`), then grant again.
  - To diagnose permission loops, run `log show --last 5m --predicate 'process == "tccd"'` and look
    for `Failed to match existing code requirement`.
  - If the keychain is locked after a reboot, unlock it with
    `security unlock-keychain -p "$(cat .signing/keychain-password)" .signing/signing.keychain-db`.
  - `.signing/` is not on GitHub. Back it up separately. On a new Mac either restore it (and
    add the keychain to the search list again) or create a new certificate and grant the
    permission again.

## Repo hygiene

- Never commit `.signing/`, keychains, `*.p12`/`*.pem`/`*.key`/`*.cer`, provisioning profiles,
  `.env*`, tokens, or build output (`.build/`, `build/`). `.gitignore` covers these, so keep it
  that way.
- Git author for this repo (local config, not global): Rodrigo Furtado <magicoppk@gmail.com>.
- Remote: `github.com/magicoppk27/screen-pointer` (private). The GitHub CLI is at `~/.local/bin/gh`.

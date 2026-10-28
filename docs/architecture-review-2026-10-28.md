# Architecture review — 2026-10-28

Screen Pointer is small: 10 Swift files and 1,800 lines, and the largest file (`DrawMode.swift`)
has 360. None of the size triggers fire, there's no god model, and no file mixes unrelated
features. The signals below come from structure, not size. Churn over the last 30 days is
spread evenly. The most-touched source files are `SettingsWindow.swift` and `HotKeys.swift`
(4 commits each), because every feature adds a row and a shortcut.

The performance fixes made in the same pass (idle timers, the draw layer split, the magnifier
queue) change no structure and aren't repeated here.

## Shared mouse tracker  [Worth exploring]

Files: CursorHighlight.swift, Magnifier.swift
Signal: duplicated plumbing. Each feature installs its own global and local `NSEvent`
monitors for the same mouse events.
Problem: with the halo and lens both on, every mouse event goes through two global and two
local monitors, and each feature repeats the install and remove bookkeeping. A third
pointer-following feature (a spotlight, say) would copy it again.
Proposal:
```swift
final class MouseTracker {
    static let shared = MouseTracker()
    /// Called on the main thread with the event's type and the mouse location.
    func subscribe(_ id: AnyHashable, _ handler: @escaping (NSEvent.EventType, NSPoint) -> Void)
    func unsubscribe(_ id: AnyHashable)   // monitors are removed when the last subscriber leaves
}
```
Benefits: one pair of monitors no matter how many features are on, and the bookkeeping lives
in one place.
Proof of same behavior: the halo follows the mouse and recolors on clicks, and the lens tracks,
both checked by hand. CPU with the halo and lens on, before and after.
Plan: (1) add MouseTracker; (2) move the halo onto it; (3) move the magnifier onto it.

## Testable pure logic  [Worth exploring]

Files: Magnifier.swift (crop math), KeystrokeOverlay.swift (merge rules), Shortcuts.swift
Signal: no tests at all, and the riskiest logic is buried inside main-thread controllers.
Problem: the lens crop rectangle (y-up orientation, edge clamping), the keystroke
merge-or-new-chip rules and the shortcut collision rules are pure functions of plain values,
but they're only exercised by hand.
Proposal: move them into plain types that take plain values (`LensGeometry.cropRect(mouse:
screen:lensSize:zoom:)`, `KeystrokeLog.append(_:at:)`), and add a test target.
Benefits: the bugs that are hardest to see by eye (edge clamping, merge timing) get fast tests.
Proof of same behavior: the new tests pin the current outputs before the move.
Plan: (1) check that `swift test` works with only the Command Line Tools; (2) extract
LensGeometry plus tests; (3) extract KeystrokeLog plus tests.
Risk: Swift Testing or XCTest may not be usable with the Command Line Tools alone. Check that
first.

## Split Support.swift by topic  [Speculative]

Files: Support.swift (121 lines: Color hex, window level, NSScreen, OverlayPanel,
InteractiveHostingView, Permissions)
Signal: a grab-bag file. Permissions code is split between Support.swift (requests, alerts)
and SettingsWindow.swift (PermissionStatus).
Proposal: `Permissions.swift` (Permissions + PermissionStatus) and `Overlay.swift`
(OverlayPanel, InteractiveHostingView, levels). Color hex stays put.
Benefits: one place for everything about permissions. A small win.
Plan: one commit that only moves code.

## Top recommendation

None of these is urgent. If one is done, do **Testable pure logic**, because it guards the parts
a regression would hide in. Do **Shared mouse tracker** only when a third pointer-following
feature is planned.

## Considered, not recommended

- A common "Feature" protocol for the four controllers. They share only on/off, and their
  lifecycles differ (event tap, stream, canvas window, panel). The protocol would be shallow.
- Replacing the singletons with dependency injection. That isn't worth it without tests that
  need it. Revisit together with "Testable pure logic".
- Moving Settings to the SwiftUI `Settings` scene. It doesn't open reliably from a menu-bar-only
  app (see CLAUDE.md), so the AppKit window stays.

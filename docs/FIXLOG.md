# Fix log

## 2026-10-28 — Draw mode showed strokes seconds late

Symptom: after the 0.4.0 performance pass, a stroke appeared only seconds after you started
drawing, or when you released the mouse.
Cause: finished strokes and the live stroke shared one `Equatable` layer that compared stroke
ids. The live stroke keeps its id while points are added, so SwiftUI treated it as unchanged and
skipped redrawing.
Fix: `CommittedStrokesLayer` (Equatable, by ids) for finished strokes, and a separate
non-Equatable `LiveStrokeLayer` for the stroke being drawn.
Check: snapshot mode writes `draw-live-{light,dark}.png`, a stroke extended point by point and
captured before it's committed. The whole curve must be visible.
Rule: only make a view Equatable when everything it draws is covered by `==`. Never use an
identity-only comparison for data that changes in place.

## 2026-10-28 — Draw toolbar couldn't be moved

Symptom: dragging the grip on the glass draw toolbar did nothing.
Cause: the drag view sat behind the grip icon (`.background`) and called
`window.performDrag(with:)`, which didn't move the non-activating, never-key toolbar panel.
Fix: `WindowDragHandle` moves the window itself (mouseDown/mouseDragged plus `setFrameOrigin`). It
sits as an `.overlay` on the grip and as a `.background` of the whole bar, so the grip and both
ends of the capsule drag it.
Check: snapshot mode writes `toolbar-hits-*.txt`, the hit-test result at the grip and both
edges, which must be `DragView`.
Rule: for borderless or non-activating panels, move the window yourself. Put a drag area on top
of decorative views, not behind them, and verify it with a hit test.

import AppKit
import SwiftUI

/// Liquid Glass on macOS 26 and later, with a material fallback on macOS 14–15.
extension View {
    /// Regular glass for a floating control, such as the draw toolbar.
    @ViewBuilder
    func controlGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        }
    }

    /// Clear glass dimmed by 35%, for text that floats over arbitrary screen content (HIG
    /// Materials: clear glass over rich media gets a dark dimming layer).
    @ViewBuilder
    func overlayGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.clear.tint(.black.opacity(0.35)), in: shape)
        } else {
            background(.black.opacity(0.72), in: shape)
        }
    }

    /// Groups neighbouring glass so it renders as one layer (never glass on glass).
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Hover state for custom controls, kept in an object because `@State` doesn't compile with the
/// Command Line Tools (see CLAUDE.md).
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// An area that drags its window, for borderless panels. It moves the window itself:
/// `performDrag` didn't move the non-activating draw toolbar panel.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        private var startMouse: NSPoint?
        private var startOrigin: NSPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startOrigin = window?.frame.origin
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startMouse, let startOrigin, let window else { return }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: startOrigin.x + now.x - startMouse.x,
                                          y: startOrigin.y + now.y - startMouse.y))
        }

        override func mouseUp(with event: NSEvent) {
            startMouse = nil
            startOrigin = nil
            NSCursor.pop()
        }
    }
}

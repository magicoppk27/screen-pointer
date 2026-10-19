import AppKit
import Combine
import SwiftUI

final class CursorState: ObservableObject {
    enum Press { case none, left, right }

    @Published var press: Press = .none
    @Published var idle = false
    @Published var rippleID = 0
    @Published var rippleIsRight = false
    @Published var rippleExpanded = false
}

/// Keeps a click-through halo centered on the mouse and recolors it on clicks.
final class CursorHighlightController {
    static let shared = CursorHighlightController()

    private let state = CursorState()
    private let side: CGFloat = 360
    private let idleDelay: TimeInterval = 1.5
    private var panel: OverlayPanel?
    private var monitors: [Any] = []
    private var idleTimer: Timer?
    private var lastActivity = Date()
    private var enabledSink: AnyCancellable?

    func start() {
        enabledSink = AppSettings.shared.$cursorEnabled
            .removeDuplicates()
            .sink { [weak self] on in on ? self?.show() : self?.hide() }
    }

    private func show() {
        guard panel == nil else { return }
        let p = OverlayPanel(size: NSSize(width: side, height: side))
        p.contentView = NSHostingView(rootView: CursorHighlightView(state: state, settings: .shared))
        panel = p
        move(to: NSEvent.mouseLocation)
        p.orderFrontRegardless()

        // Mouse events can be monitored globally without any permission prompt.
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        ]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(m)
        }

        lastActivity = Date()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idle = self.state.press == .none && Date().timeIntervalSince(self.lastActivity) > self.idleDelay
            if idle != self.state.idle { self.state.idle = idle }
        }
    }

    private func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        idleTimer?.invalidate()
        idleTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            state.press = .left
            ripple(right: false)
        case .rightMouseDown:
            state.press = .right
            ripple(right: true)
        case .leftMouseUp, .rightMouseUp:
            state.press = .none
        default:
            break
        }
        move(to: NSEvent.mouseLocation)
        lastActivity = Date()
        if state.idle { state.idle = false }
    }

    private func ripple(right: Bool) {
        state.rippleIsRight = right
        state.rippleExpanded = false
        state.rippleID += 1
        DispatchQueue.main.async { [state] in
            withAnimation(.easeOut(duration: 0.45)) { state.rippleExpanded = true }
        }
    }

    private func move(to point: NSPoint) {
        panel?.setFrameOrigin(NSPoint(x: point.x - side / 2, y: point.y - side / 2))
    }
}

struct CursorHighlightView: View {
    @ObservedObject var state: CursorState
    @ObservedObject var settings: AppSettings

    var body: some View {
        let size = settings.cursorSize
        let color: Color = switch state.press {
        case .none: settings.cursorColor
        case .left: settings.leftClickColor
        case .right: settings.rightClickColor
        }

        ZStack {
            if state.rippleID > 0 {
                RippleView(color: state.rippleIsRight ? settings.rightClickColor : settings.leftClickColor,
                           size: size, expanded: state.rippleExpanded)
            }
            ZStack {
                Circle().fill(color.opacity(settings.fillOpacity))
                Circle().strokeBorder(color, lineWidth: settings.ringWidth)
            }
            .frame(width: size, height: size)
            .scaleEffect(state.press == .none ? 1 : 0.8)
            .opacity(state.idle ? settings.inactiveOpacity : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: state.press)
            .animation(.easeInOut(duration: 0.4), value: state.idle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RippleView: View {
    let color: Color
    let size: CGFloat
    let expanded: Bool

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(expanded ? 2 : 0.8)
            .opacity(expanded ? 0 : 0.9)
    }
}

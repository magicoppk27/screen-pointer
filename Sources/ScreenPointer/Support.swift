import AppKit
import SwiftUI

extension Color {
    /// Accepts "#RRGGBB" or "#RRGGBBAA".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let hasAlpha = s.count == 8
        let rgb = hasAlpha ? v >> 8 : v
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: hasAlpha ? Double(v & 0xFF) / 255 : 1
        )
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X",
                      byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent), byte(c.alphaComponent))
    }
}

extension NSWindow.Level {
    /// Above full-screen apps and the draw canvas.
    static let overlay = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
}

extension NSScreen {
    static var withMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }
}

/// A transparent, click-through panel that floats over everything on every Space.
final class OverlayPanel: NSPanel {
    init(size: NSSize, level: NSWindow.Level = .overlay) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that takes the first click and reports right-clicks.
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick() } else { super.rightMouseDown(with: event) }
    }
}

enum Permissions {
    static let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    static func openInputMonitoringSettings() {
        NSWorkspace.shared.open(inputMonitoringURL)
    }

    static func showInputMonitoringAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Input Monitoring permission needed"
        alert.informativeText = """
        Screen Pointer needs Input Monitoring to show your keystrokes.
        Enable it in System Settings → Privacy & Security → Input Monitoring, then turn on Show Keystrokes again.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openInputMonitoringSettings()
        }
    }
}

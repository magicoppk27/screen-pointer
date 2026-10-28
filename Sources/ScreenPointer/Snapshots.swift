import AppKit
import ScreenCaptureKit
import SwiftUI

/// Review mode: `ScreenPointer --snapshot <folder>` writes light and dark PNGs of every Settings tab,
/// the draw toolbar and the keystroke bubbles, then quits. Overlays are captured with the real
/// screen behind them, so glass looks as it does in use. It changes no settings and registers no
/// hotkeys, so it can run next to the normal app.
enum Snapshots {
    static var requestedFolder: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(into folder: URL) {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSApp.activate(ignoringOtherApps: true) // capture Settings as the key window
                for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: name)
                    try await settingsTabs(mode: mode, folder: folder)
                    try await toolbar(mode: mode, folder: folder)
                    try await keystrokes(mode: mode, folder: folder)
                    try await liveStroke(mode: mode, folder: folder)
                }
                print("snapshots written to \(folder.path)")
            } catch {
                print("snapshot failed: \(error)")
            }
            exit(0)
        }
    }

    @MainActor
    private static func settingsTabs(mode: String, folder: URL) async throws {
        let controller = SettingsWindowController.shared
        for tab in SettingsTab.allCases {
            controller.show(tab: tab)
            try await Task.sleep(for: .milliseconds(700))
            guard let window = controller.window else { continue }
            try await save(windowImage(window), folder: folder, name: "settings-\(tab.rawValue)-\(mode)")
        }
        controller.window?.orderOut(nil)
    }

    @MainActor
    private static func toolbar(mode: String, folder: URL) async throws {
        let model = DrawModel()
        model.tool = .arrow
        let panel = DrawController.makeToolbarPanel(model: model) {}
        try await showCentered(panel, name: "toolbar-\(mode)", folder: folder, keepOpen: true)
        // Probe: clicks on the grip and between buttons must land on the drag handle.
        if let content = panel.contentView {
            let midY = content.bounds.midY
            var report = ""
            let inset: CGFloat = 14 + 8           // panel padding + capsule padding
            let grip: CGFloat = inset + 9          // centre of the 18 pt grip
            let gap: CGFloat = inset + 18 + 28 * 7 + 6 // past the 7 tool buttons, inside the separator gap
            let edge: CGFloat = 14 + 3              // inside the capsule, left of the grip
            let right: CGFloat = content.bounds.maxX - 14 - 3
            let points: [(String, CGFloat)] = [("grip", grip), ("separator gap", gap),
                                               ("left edge", edge), ("right edge", right)]
            for (label, x) in points {
                let hit = content.hitTest(NSPoint(x: x, y: midY))
                report += "\(label) at x=\(Int(x)): \(hit.map { String(describing: type(of: $0)) } ?? "nil")\n"
            }
            try report.write(to: folder.appendingPathComponent("toolbar-hits-\(mode).txt"), atomically: true, encoding: .utf8)
        }
        panel.orderOut(nil)
    }

    @MainActor
    private static func keystrokes(mode: String, folder: URL) async throws {
        let model = KeystrokeModel()
        model.entries = [
            .init(text: "⌘⇧4", updated: .now, isCombo: true),
            .init(text: "Hello from Screen Pointer", updated: .now, isCombo: false),
        ]
        let panel = OverlayPanel(size: NSSize(width: 900, height: 200))
        panel.contentView = NSHostingView(rootView: KeystrokeOverlayView(model: model, settings: .shared))
        try await showCentered(panel, name: "keystrokes-\(mode)", folder: folder)
    }

    /// Probe for draw-mode lag: extends a stroke the way a drag does, then captures it before it's
    /// committed. The stroke must be visible in `draw-live-*.png`.
    @MainActor
    private static func liveStroke(mode: String, folder: URL) async throws {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - 200, y: f.midY - 120, width: 400, height: 240)
        let model = DrawModel()
        let window = DrawWindow(frame: rect)
        window.contentView = NSHostingView(rootView: DrawCanvasView(model: model, settings: .shared))
        window.orderFrontRegardless()
        model.current = DrawStroke(tool: .pen, color: .red, width: 8, points: [CGPoint(x: 40, y: 120)])
        try await Task.sleep(for: .milliseconds(300))
        for i in 1...30 {
            model.current?.points.append(CGPoint(x: 40 + Double(i) * 10, y: 120 + 60 * sin(Double(i) / 4)))
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(100))
        try await save(regionImage(rect, on: screen), folder: folder, name: "draw-live-\(mode)")
        window.orderOut(nil)
    }

    @MainActor
    private static func showCentered(_ panel: NSPanel, name: String, folder: URL, keepOpen: Bool = false) async throws {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2))
        panel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(600))
        try await save(regionImage(panel.frame, on: screen), folder: folder, name: name)
        if !keepOpen { panel.orderOut(nil) }
    }

    // MARK: Capture

    @MainActor
    private static func windowImage(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let config = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: config)
    }

    /// A region of the screen, with whatever is behind the overlay, in Cocoa coordinates.
    @MainActor
    private static func regionImage(_ rect: NSRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let config = SCStreamConfiguration()
        // sourceRect is in display points with a top-left origin.
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                   y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.width = Int(rect.width * screen.backingScaleFactor)
        config.height = Int(rect.height * screen.backingScaleFactor)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
    }

    private static func save(_ image: CGImage, folder: URL, name: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

import SwiftUI

@main
struct ScreenPointerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Screen Pointer", systemImage: "cursorarrow.rays") {
            MenuContent(settings: .shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let folder = Snapshots.requestedFolder {
            Snapshots.run(into: folder) // review mode: no overlays, no hotkeys, settings untouched
            return
        }
        CursorHighlightController.shared.start()
        KeystrokeController.shared.start()
        HotKeyCenter.shared.register()
    }
}

enum Features {
    /// Switches off every overlay (highlight, keystrokes, drawing, magnifier). The app stays in
    /// the menu bar.
    static func turnOffAll() {
        AppSettings.shared.cursorEnabled = false
        AppSettings.shared.keystrokesEnabled = false
        DrawController.shared.stop()
        MagnifierController.shared.stop()
    }
}

private struct MenuContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var magnifier = MagnifierController.shared
    @ObservedObject var shortcuts = ShortcutStore.shared

    var body: some View {
        Toggle("Highlight Cursor", isOn: $settings.cursorEnabled)
            .keyboardShortcut(shortcuts.shortcut(for: .cursor).keyboardShortcut)
        Toggle("Show Keystrokes", isOn: $settings.keystrokesEnabled)
            .keyboardShortcut(shortcuts.shortcut(for: .keystrokes).keyboardShortcut)
        Button("Draw on Screen") { DrawController.shared.toggle() }
            .keyboardShortcut(shortcuts.shortcut(for: .draw).keyboardShortcut)
        Toggle("Magnifier", isOn: Binding(get: { magnifier.isActive }, set: { _ in magnifier.toggle() }))
            .keyboardShortcut(shortcuts.shortcut(for: .magnifier).keyboardShortcut)
        Divider()
        Button("Turn Off All Features") { Features.turnOffAll() }
            .keyboardShortcut(shortcuts.shortcut(for: .turnOffAll).keyboardShortcut)
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit Screen Pointer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

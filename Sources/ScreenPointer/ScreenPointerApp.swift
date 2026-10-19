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
        CursorHighlightController.shared.start()
        KeystrokeController.shared.start()
        HotKeyCenter.shared.register()
    }
}

private struct MenuContent: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Toggle("Highlight Cursor", isOn: $settings.cursorEnabled)
            .keyboardShortcut("c", modifiers: [.control, .option])
        Toggle("Show Keystrokes", isOn: $settings.keystrokesEnabled)
            .keyboardShortcut("k", modifiers: [.control, .option])
        Button("Draw on Screen") { DrawController.shared.toggle() }
            .keyboardShortcut("d", modifiers: [.control, .option])
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit Screen Pointer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

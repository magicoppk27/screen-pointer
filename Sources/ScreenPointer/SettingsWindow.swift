import AppKit
import SwiftUI

/// Plain AppKit window: SwiftUI's Settings scene is unreliable to open from a menu-bar-only app.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            w.title = "Screen Pointer Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Re-checked whenever the app becomes active (e.g. after returning from System Settings).
final class PermissionStatus: ObservableObject {
    static let shared = PermissionStatus()
    @Published private(set) var hasInputMonitoring = Permissions.hasInputMonitoring
    @Published private(set) var hasScreenRecording = Permissions.hasScreenRecording

    func refresh() {
        hasInputMonitoring = Permissions.hasInputMonitoring
        hasScreenRecording = Permissions.hasScreenRecording
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var permissions = PermissionStatus.shared

    var body: some View {
        Form {
            Section("Cursor Highlight") {
                Toggle("Highlight cursor", isOn: $settings.cursorEnabled)
                ColorPicker("Highlight color", selection: $settings.cursorColor, supportsOpacity: false)
                SliderRow(title: "Size", value: $settings.cursorSize, range: 20...150, format: "%.0f pt")
                SliderRow(title: "Ring width", value: $settings.ringWidth, range: 0...12, format: "%.0f pt")
                SliderRow(title: "Fill opacity", value: $settings.fillOpacity, range: 0...0.8, format: "%.0f%%", scale: 100)
                SliderRow(title: "Idle opacity", value: $settings.inactiveOpacity, range: 0...1, format: "%.0f%%", scale: 100)
                ColorPicker("Left click", selection: $settings.leftClickColor, supportsOpacity: false)
                ColorPicker("Right click", selection: $settings.rightClickColor, supportsOpacity: false)
            }

            Section("Keystrokes") {
                Toggle("Show keystrokes", isOn: $settings.keystrokesEnabled)
                SliderRow(title: "Text size", value: $settings.keystrokeFontSize, range: 14...64, format: "%.0f pt")
                LabeledContent("Input Monitoring") {
                    if permissions.hasInputMonitoring {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") { Permissions.openInputMonitoringSettings() }
                    }
                }
            }

            Section("Drawing") {
                ColorPicker("Default color", selection: $settings.drawColor, supportsOpacity: false)
                SliderRow(title: "Line width", value: $settings.drawLineWidth, range: 1...20, format: "%.0f pt")
                Text("Esc or right-click exits. ⌘Z undoes. The hand button lets clicks pass through to apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Magnifier") {
                SliderRow(title: "Zoom", value: $settings.magnifierZoom, range: 1.5...10, format: "%.1f×")
                SliderRow(title: "Lens size", value: $settings.magnifierSize, range: 120...520, format: "%.0f pt")
                LabeledContent("Screen Recording") {
                    if permissions.hasScreenRecording {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") { Permissions.openScreenRecordingSettings() }
                    }
                }
                Text("Tap ⌃⌥M to toggle the lens, or hold it to show the lens only while held. To use a mouse button, map it to ⌃⌥M in your mouse's software.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                LabeledContent("Toggle cursor highlight", value: "⌃⌥C")
                LabeledContent("Toggle keystrokes", value: "⌃⌥K")
                LabeledContent("Draw on screen", value: "⌃⌥D")
                LabeledContent("Magnifier (tap or hold)", value: "⌃⌥M")
                LabeledContent("Zoom in / out (lens showing)", value: "⌃⌥=  ⌃⌥-")
            }

            Section {
                Button("Reset Appearance to Defaults") { settings.resetAppearance() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var scale: Double = 1

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(String(format: format, value * scale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

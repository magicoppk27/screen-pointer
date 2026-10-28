import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case cursor, keystrokes, drawing, magnifier, shortcuts

    var title: String {
        switch self {
        case .cursor: "Cursor"
        case .keystrokes: "Keystrokes"
        case .drawing: "Drawing"
        case .magnifier: "Magnifier"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .cursor: "cursorarrow.rays"
        case .keystrokes: "keyboard"
        case .drawing: "pencil.tip.crop.circle"
        case .magnifier: "plus.magnifyingglass"
        case .shortcuts: "command"
        }
    }
}

/// An AppKit window with toolbar tabs, because SwiftUI's Settings scene doesn't open reliably from a
/// menu-bar-only app (see CLAUDE.md). Each tab is one grouped Form; the window resizes to fit
/// the selected tab and reopens on the tab used last.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    fileprivate static let lastTabKey = "settingsTab"
    private(set) var window: NSWindow?

    func show(tab: SettingsTab? = nil) {
        if window == nil { window = makeWindow() }
        if let tab { select(tab) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil) // opens calm: no focus ring on the first control
    }

    func select(_ tab: SettingsTab) {
        guard let tabs = window?.contentViewController as? SettingsTabsController,
              let index = SettingsTab.allCases.firstIndex(of: tab) else { return }
        tabs.selectedTabViewItemIndex = index
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabsController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPane(tab: tab))
            host.sizingOptions = [.preferredContentSize]
            host.title = tab.title // the window title follows the selected tab
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        if let saved = UserDefaults.standard.string(forKey: Self.lastTabKey),
           let index = SettingsTab.allCases.firstIndex(where: { $0.rawValue == saved }) {
            tabs.selectedTabViewItemIndex = index
        }
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.delegate = self
        tabs.fitWindowToSelectedTab(animate: false)
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutStore.shared.stopRecording()
    }
}

final class SettingsTabsController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let id = item?.identifier as? String {
            UserDefaults.standard.set(id, forKey: SettingsWindowController.lastTabKey)
        }
        ShortcutStore.shared.stopRecording()
        fitWindowToSelectedTab(animate: view.window?.isVisible ?? false)
        view.window?.makeFirstResponder(nil)
    }

    /// Sizes the window to the selected pane, keeping its top edge in place.
    func fitWindowToSelectedTab(animate: Bool) {
        guard selectedTabViewItemIndex >= 0,
              let pane = tabViewItems[selectedTabViewItemIndex].viewController,
              let window = view.window ?? pane.view.window else { return }
        pane.view.layoutSubtreeIfNeeded()
        let size = pane.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animate)
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

struct SettingsPane: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .cursor: CursorSettings()
            case .keystrokes: KeystrokeSettings()
            case .drawing: DrawingSettings()
            case .magnifier: MagnifierSettings()
            case .shortcuts: ShortcutSettings()
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            PermissionStatus.shared.refresh()
        }
    }
}

// MARK: Tabs

private struct CursorSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Highlight the cursor", isOn: $settings.cursorEnabled)
            }
            Section("Halo") {
                ColorPicker("Color", selection: $settings.cursorColor, supportsOpacity: false)
                SliderRow(title: "Size", value: $settings.cursorSize, range: 20...150, format: "%.0f pt")
                SliderRow(title: "Ring width", value: $settings.ringWidth, range: 0...12, format: "%.0f pt")
                SliderRow(title: "Fill", value: $settings.fillOpacity, range: 0...0.8, format: "%.0f%%", scale: 100)
                SliderRow(title: "Opacity when idle", value: $settings.inactiveOpacity, range: 0...1, format: "%.0f%%", scale: 100)
            }
            Section {
                ColorPicker("Left click", selection: $settings.leftClickColor, supportsOpacity: false)
                ColorPicker("Right click", selection: $settings.rightClickColor, supportsOpacity: false)
            } header: {
                Text("Clicks")
            } footer: {
                SectionFooter("The halo turns this color while the button is held.")
            }
            Section {
                Button("Restore Default Appearance…") {
                    confirm(title: "Restore default appearance?",
                            message: "Colors, sizes and opacity go back to their defaults in every tab. Shortcuts don't change.",
                            action: "Restore") { settings.resetAppearance() }
                }
            }
        }
    }
}

private struct KeystrokeSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionStatus.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show keystrokes on screen", isOn: $settings.keystrokesEnabled)
            }
            Section("Appearance") {
                SliderRow(title: "Text size", value: $settings.keystrokeFontSize, range: 14...64, format: "%.0f pt")
            }
            Section {
                PermissionRow(name: "Input Monitoring", allowed: permissions.hasInputMonitoring,
                              open: Permissions.openInputMonitoringSettings)
            } header: {
                Text("Permission")
            } footer: {
                SectionFooter("Needed to see keys typed in other apps. Nothing is stored or sent.")
            }
        }
    }
}

private struct DrawingSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ColorPicker("Pen color", selection: $settings.drawColor, supportsOpacity: false)
                SliderRow(title: "Line width", value: $settings.drawLineWidth, range: 1...20, format: "%.0f pt")
            } header: {
                Text("Defaults")
            } footer: {
                SectionFooter("Esc or right-click exits drawing. ⌘Z undoes. The hand button lets clicks pass through to apps while your drawings stay.")
            }
        }
    }
}

private struct MagnifierSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionStatus.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared

    var body: some View {
        Form {
            Section {
                SliderRow(title: "Zoom", value: $settings.magnifierZoom, range: 1.5...10, format: "%.1f×")
                SliderRow(title: "Lens size", value: $settings.magnifierSize, range: 120...520, format: "%.0f pt")
            } header: {
                Text("Lens")
            } footer: {
                SectionFooter("Tap \(shortcuts.shortcut(for: .magnifier).display) to toggle the lens, or hold it to show the lens only while held. Esc or \(shortcuts.shortcut(for: .closeLens).display) closes it. To use a mouse button, map it to \(shortcuts.shortcut(for: .magnifier).display) in your mouse's software.")
            }
            Section {
                PermissionRow(name: "Screen Recording", allowed: permissions.hasScreenRecording,
                              open: Permissions.openScreenRecordingSettings)
            } header: {
                Text("Permission")
            } footer: {
                SectionFooter("Needed to see what's under the cursor. Nothing is recorded or saved.")
            }
        }
    }
}

private struct ShortcutSettings: View {
    @ObservedObject private var shortcuts = ShortcutStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(action: action, store: shortcuts)
                }
                LabeledContent("Close lens (always)", value: "Esc")
            } footer: {
                SectionFooter("Click a shortcut, then press the new keys. Global shortcuts need ⌃, ⌥ or ⌘.")
            }
            Section {
                Button("Restore Default Shortcuts…") {
                    confirm(title: "Restore default shortcuts?",
                            message: "Every shortcut goes back to its default.",
                            action: "Restore") { shortcuts.resetAll() }
                }
                .disabled(!ShortcutAction.allCases.contains(where: shortcuts.isCustomized))
            }
        }
    }
}

// MARK: Rows

/// Section help text: leading-aligned and secondary, like System Settings.
private struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionRow: View {
    let name: String
    let allowed: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent(name) {
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Label("Not allowed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings", action: open)
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore

    private var isRecording: Bool { store.recording == action }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if store.unavailable.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Another app is already using this shortcut. Record a different one.")
                }
                Button {
                    isRecording ? store.stopRecording() : store.startRecording(action)
                } label: {
                    Text(isRecording ? "Type shortcut…" : store.shortcut(for: action).display)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 96)
                }
                .tint(isRecording ? .accentColor : nil)
                .buttonStyle(.bordered)
                .help(isRecording ? "Press the new keys, or Esc to cancel" : "Click to record a new shortcut")
                Button {
                    store.reset(action)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(action.defaultShortcut.display)")
                .accessibilityLabel("Reset to \(action.defaultShortcut.display)")
                .opacity(store.isCustomized(action) ? 1 : 0)
                .disabled(!store.isCustomized(action))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if isRecording, let message = store.recordingMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
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

/// A confirmation alert attached to the Settings window (a sheet), for restoring defaults.
private func confirm(title: String, message: String, action: String, perform: @escaping () -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: action)
    alert.addButton(withTitle: "Cancel")
    if let window = SettingsWindowController.shared.window {
        alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { perform() } }
    } else if alert.runModal() == .alertFirstButtonReturn {
        perform()
    }
}

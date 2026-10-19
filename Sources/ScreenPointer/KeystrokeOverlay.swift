import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class KeystrokeModel: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        var text: String
        var updated: Date
        /// Shortcuts and special keys get their own chip; plain typing is merged into one line.
        var isCombo: Bool
    }

    @Published var entries: [Entry] = []
}

/// Listens to key-down events through a listen-only event tap (needs Input
/// Monitoring) and shows them in a fading overlay near the bottom of the screen.
final class KeystrokeController {
    static let shared = KeystrokeController()

    let model = KeystrokeModel()
    private let maxEntries = 4
    private let lifetime: TimeInterval = 2.0
    private let mergeWindow: TimeInterval = 1.2
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var panel: OverlayPanel?
    private var pruneTimer: Timer?
    private var enabledSink: AnyCancellable?

    func start() {
        enabledSink = AppSettings.shared.$keystrokesEnabled
            .removeDuplicates()
            // Hop off the willSet callback: enable() may switch the setting back off.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.enable() : self?.disable() }
    }

    private func enable() {
        guard tap == nil else { return }
        if !Permissions.hasInputMonitoring {
            CGRequestListenEventAccess()
            if !Permissions.hasInputMonitoring {
                AppSettings.shared.keystrokesEnabled = false
                Permissions.showInputMonitoringAlert()
                return
            }
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                Unmanaged<KeystrokeController>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AppSettings.shared.keystrokesEnabled = false
            Permissions.showInputMonitoringAlert()
            return
        }

        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)

        let p = OverlayPanel(size: NSSize(width: 900, height: 360))
        p.contentView = NSHostingView(rootView: KeystrokeOverlayView(model: model, settings: .shared))
        panel = p
        positionPanel()
        p.orderFrontRegardless()

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.prune() }
    }

    private func disable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
        panel?.orderOut(nil)
        panel = nil
        model.entries.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let isShortcut = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        let now = Date()

        withAnimation(.easeOut(duration: 0.15)) {
            if isShortcut || KeyFormatter.isSpecial(keyCode) {
                let text = KeyFormatter.modifiers(flags) + KeyFormatter.keyName(keyCode: keyCode, event: event)
                if isRepeat, let i = model.entries.indices.last, model.entries[i].isCombo, model.entries[i].text == text {
                    model.entries[i].updated = now
                } else {
                    model.entries.append(.init(text: text, updated: now, isCombo: true))
                }
            } else {
                let typed = KeyFormatter.typedCharacters(event)
                guard !typed.isEmpty else { return }
                if let i = model.entries.indices.last, !model.entries[i].isCombo,
                   now.timeIntervalSince(model.entries[i].updated) < mergeWindow {
                    model.entries[i].text = String((model.entries[i].text + typed).suffix(40))
                    model.entries[i].updated = now
                } else {
                    model.entries.append(.init(text: typed, updated: now, isCombo: false))
                }
            }
            if model.entries.count > maxEntries {
                model.entries.removeFirst(model.entries.count - maxEntries)
            }
        }
        positionPanel()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        guard model.entries.contains(where: { $0.updated < cutoff }) else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            model.entries.removeAll { $0.updated < cutoff }
        }
    }

    /// Follows the screen the mouse is on.
    private func positionPanel() {
        guard let panel, let screen = NSScreen.withMouse else { return }
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 40))
    }
}

enum KeyFormatter {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "␣",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Space is only special when combined with a modifier.
    static func isSpecial(_ keyCode: Int) -> Bool {
        keyCode != kVK_Space && special[keyCode] != nil
    }

    static func modifiers(_ flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s
    }

    static func keyName(keyCode: Int, event: CGEvent) -> String {
        if let name = special[keyCode] { return name }
        return (NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? "").uppercased()
    }

    static func typedCharacters(_ event: CGEvent) -> String {
        NSEvent(cgEvent: event)?.characters ?? ""
    }
}

struct KeystrokeOverlayView: View {
    @ObservedObject var model: KeystrokeModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.entries) { entry in
                Text(entry.text)
                    .font(.system(size: settings.keystrokeFontSize, weight: .semibold,
                                  design: entry.isCombo ? .rounded : .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.72))
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

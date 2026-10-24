import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt32
    /// What to print for the key itself, e.g. "M", "=", "F5", "←".
    var key: String

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    /// Same combo for the purposes of conflicts and registration.
    func collides(with other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// For showing the shortcut next to menu items; nil when SwiftUI can't express the key.
    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch keyCode {
        case kVK_LeftArrow: equivalent = .leftArrow
        case kVK_RightArrow: equivalent = .rightArrow
        case kVK_UpArrow: equivalent = .upArrow
        case kVK_DownArrow: equivalent = .downArrow
        case kVK_Return: equivalent = .return
        case kVK_Tab: equivalent = .tab
        case kVK_Space: equivalent = .space
        case kVK_Delete: equivalent = .delete
        default:
            guard key.count == 1, let c = key.lowercased().first else { return nil }
            equivalent = KeyEquivalent(c)
        }
        var mods: SwiftUI.EventModifiers = []
        if modifiers & UInt32(controlKey) != 0 { mods.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { mods.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { mods.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { mods.insert(.command) }
        return KeyboardShortcut(equivalent, modifiers: mods)
    }

    static func controlOption(_ keyCode: Int, _ key: String) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey), key: key)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func keyLabel(for event: NSEvent) -> String {
        let code = Int(event.keyCode)
        if code == kVK_Space { return "Space" }
        if let name = KeyFormatter.specialName(for: code) { return name }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        return chars.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Key \(code)" : chars
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case cursor, keystrokes, draw, magnifier, turnOffAll, zoomIn, zoomOut, closeLens

    var id: Self { self }

    var title: String {
        switch self {
        case .cursor: "Toggle cursor highlight"
        case .keystrokes: "Toggle keystrokes"
        case .draw: "Draw on screen"
        case .magnifier: "Magnifier (tap or hold)"
        case .turnOffAll: "Turn off all features"
        case .zoomIn: "Zoom in (lens showing)"
        case .zoomOut: "Zoom out (lens showing)"
        case .closeLens: "Close lens (lens showing)"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .cursor: .controlOption(kVK_ANSI_C, "C")
        case .keystrokes: .controlOption(kVK_ANSI_K, "K")
        case .draw: .controlOption(kVK_ANSI_D, "D")
        case .magnifier: .controlOption(kVK_ANSI_M, "M")
        case .turnOffAll: .controlOption(kVK_ANSI_X, "X")
        case .zoomIn: .controlOption(kVK_ANSI_Equal, "=")
        case .zoomOut: .controlOption(kVK_ANSI_Minus, "-")
        case .closeLens: Shortcut(keyCode: kVK_ANSI_X, modifiers: 0, key: "X")
        }
    }

    /// Global shortcuts are always registered, so they must include ⌃, ⌥ or ⌘ to avoid
    /// hijacking ordinary typing. Lens-only keys may be bare keys.
    var isGlobal: Bool {
        switch self {
        case .cursor, .keystrokes, .draw, .magnifier, .turnOffAll: true
        case .zoomIn, .zoomOut, .closeLens: false
        }
    }

    /// Carbon hot key ID. 7 is reserved for the fixed Esc binding.
    var hotKeyID: UInt32 {
        switch self {
        case .cursor: 1
        case .keystrokes: 2
        case .draw: 3
        case .magnifier: 4
        case .zoomIn: 5
        case .zoomOut: 6
        case .closeLens: 8
        case .turnOffAll: 9
        }
    }
}

/// The user's shortcuts (persisted), plus the recorder used by the Settings window.
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    private static let defaultsKey = "shortcuts"

    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]
    /// Shortcuts that couldn't be registered, usually because another app owns the combo.
    @Published var unavailable: Set<ShortcutAction> = []
    @Published private(set) var recording: ShortcutAction?
    @Published private(set) var recordingMessage: String?

    private var monitor: Any?

    private init() {
        var loaded: [ShortcutAction: Shortcut] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (raw, shortcut) in saved {
                if let action = ShortcutAction(rawValue: raw) { loaded[action] = shortcut }
            }
        }
        shortcuts = loaded
    }

    func shortcut(for action: ShortcutAction) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func isCustomized(_ action: ShortcutAction) -> Bool {
        shortcut(for: action) != action.defaultShortcut
    }

    func conflict(for shortcut: Shortcut, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.shortcut(for: $0).collides(with: shortcut) }
    }

    func set(_ shortcut: Shortcut, for action: ShortcutAction) {
        shortcuts[action] = shortcut == action.defaultShortcut ? nil : shortcut
        save()
        HotKeyCenter.shared.rebind()
    }

    func reset(_ action: ShortcutAction) {
        // A default can collide with another action's custom shortcut; reset that one too.
        if let other = conflict(for: action.defaultShortcut, excluding: action) {
            shortcuts[other] = nil
        }
        shortcuts[action] = nil
        save()
        HotKeyCenter.shared.rebind()
    }

    func resetAll() {
        shortcuts.removeAll()
        save()
        HotKeyCenter.shared.rebind()
    }

    private func save() {
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: Recording

    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        recordingMessage = action.isGlobal ? "Press keys with ⌃, ⌥ or ⌘ · Esc cancels" : "Press a key · Esc cancels"
        // Release all hotkeys so pressing an existing combo is captured instead of triggered.
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording != nil else { return }
        recording = nil
        recordingMessage = nil
        HotKeyCenter.shared.resume()
    }

    private func record(_ event: NSEvent) {
        guard let action = recording else { return }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if Int(event.keyCode) == kVK_Escape && flags.isEmpty {
            stopRecording()
            return
        }
        if action.isGlobal && flags.intersection([.control, .option, .command]).isEmpty {
            recordingMessage = "Include ⌃, ⌥ or ⌘ so normal typing isn't affected"
            NSSound.beep()
            return
        }
        let shortcut = Shortcut(keyCode: Int(event.keyCode),
                                modifiers: Shortcut.carbonModifiers(flags),
                                key: Shortcut.keyLabel(for: event))
        if let other = conflict(for: shortcut, excluding: action) {
            recordingMessage = "\(shortcut.display) is already used by “\(other.title)”"
            NSSound.beep()
            return
        }
        // Commit after resuming so the new combo gets registered (and checked for clashes).
        stopRecording()
        set(shortcut, for: action)
    }
}

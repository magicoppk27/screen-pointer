import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon's RegisterEventHotKey (no permission needed). The combos come
/// from ShortcutStore and are editable in Settings → Shortcuts. Defaults:
///   ⌃⌥C  toggle cursor highlight
///   ⌃⌥K  toggle keystroke overlay
///   ⌃⌥D  toggle draw mode
///   ⌃⌥M  magnifier (tap to toggle, hold for a momentary lens)
///   ⌃⌥X  turn off all features (the app keeps running)
///   ⌃⌥= / ⌃⌥-  zoom in / out   ┐ only registered while the magnifier is showing,
///   X (and always Esc)  close   ┘ so they don't affect other apps otherwise
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Handler {
        let press: () -> Void
        let release: (() -> Void)?
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let shortcut: Shortcut
    }

    private static let escapeID: UInt32 = 7
    private static let escape = Shortcut(keyCode: kVK_Escape, modifiers: 0, key: "Esc")

    private var handlers: [ShortcutAction: Handler] = [:]
    private var escapeHandler: Handler?
    private var registered: [UInt32: Registration] = [:]
    private var handlersByID: [UInt32: Handler] = [:]
    private var suspended = false
    private var eventHandler: EventHandlerRef?

    func register() {
        guard eventHandler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async { HotKeyCenter.shared.fire(hotKeyID.id, released: released) }
            return noErr
        }, specs.count, &specs, nil, &eventHandler)

        handlers[.cursor] = Handler(press: { AppSettings.shared.cursorEnabled.toggle() }, release: nil)
        handlers[.keystrokes] = Handler(press: { AppSettings.shared.keystrokesEnabled.toggle() }, release: nil)
        handlers[.draw] = Handler(press: { DrawController.shared.toggle() }, release: nil)
        handlers[.magnifier] = Handler(press: { MagnifierController.shared.hotKeyPressed() },
                                       release: { MagnifierController.shared.hotKeyReleased() })
        handlers[.turnOffAll] = Handler(press: { Features.turnOffAll() }, release: nil)
        rebind()
    }

    /// Binds a lens-only action while the magnifier is showing.
    func bind(_ action: ShortcutAction, onPress: @escaping () -> Void) {
        handlers[action] = Handler(press: onPress, release: nil)
        rebind()
    }

    func unbind(_ actions: [ShortcutAction]) {
        actions.forEach { handlers[$0] = nil }
        rebind()
    }

    func bindEscape(_ action: (() -> Void)?) {
        escapeHandler = action.map { Handler(press: $0, release: nil) }
        rebind()
    }

    /// Unregisters everything, e.g. while the Settings window records a new shortcut.
    func suspend() {
        suspended = true
        rebind()
    }

    func resume() {
        suspended = false
        rebind()
    }

    /// Makes the registered hot keys match the current handlers and ShortcutStore. Unchanged
    /// registrations are left alone, so a hot key that's being held keeps delivering its release.
    func rebind() {
        var wanted: [UInt32: (Shortcut, Handler, ShortcutAction?)] = [:]
        if !suspended {
            for (action, handler) in handlers {
                wanted[action.hotKeyID] = (ShortcutStore.shared.shortcut(for: action), handler, action)
            }
            if let escapeHandler {
                wanted[Self.escapeID] = (Self.escape, escapeHandler, nil)
            }
        }

        for (id, registration) in registered {
            if let (shortcut, _, _) = wanted[id], shortcut.collides(with: registration.shortcut) { continue }
            UnregisterEventHotKey(registration.ref)
            registered[id] = nil
        }

        var unavailable = Set<ShortcutAction>()
        handlersByID = [:]
        for (id, (shortcut, handler, action)) in wanted {
            handlersByID[id] = handler
            guard registered[id] == nil else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5350_4E54), id: id) // 'SPNT'
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[id] = Registration(ref: ref, shortcut: shortcut)
            } else {
                NSLog("Screen Pointer: hotkey \(shortcut.display) is already taken (status \(status))")
                if let action { unavailable.insert(action) }
            }
        }
        if !suspended, ShortcutStore.shared.unavailable != unavailable {
            ShortcutStore.shared.unavailable = unavailable
        }
    }

    private func fire(_ id: UInt32, released: Bool) {
        guard let handler = handlersByID[id] else { return }
        if released { handler.release?() } else { handler.press() }
    }
}

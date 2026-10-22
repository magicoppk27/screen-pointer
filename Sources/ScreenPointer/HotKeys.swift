import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon's RegisterEventHotKey (no permission needed).
///   ⌃⌥C  toggle cursor highlight
///   ⌃⌥K  toggle keystroke overlay
///   ⌃⌥D  toggle draw mode
///   ⌃⌥M  magnifier (tap to toggle, hold for a momentary lens)
///   ⌃⌥= / ⌃⌥-  zoom in / out (only registered while the magnifier is showing)
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum ID: UInt32 {
        case cursor = 1, keystrokes, draw, magnifier, zoomIn, zoomOut
    }

    static let controlOption = UInt32(controlKey | optionKey)

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var pressActions: [UInt32: () -> Void] = [:]
    private var releaseActions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    func register() {
        guard handler == nil else { return }
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
        }, specs.count, &specs, nil, &handler)

        add(.cursor, keyCode: kVK_ANSI_C) { AppSettings.shared.cursorEnabled.toggle() }
        add(.keystrokes, keyCode: kVK_ANSI_K) { AppSettings.shared.keystrokesEnabled.toggle() }
        add(.draw, keyCode: kVK_ANSI_D) { DrawController.shared.toggle() }
        add(.magnifier, keyCode: kVK_ANSI_M,
            onPress: { MagnifierController.shared.hotKeyPressed() },
            onRelease: { MagnifierController.shared.hotKeyReleased() })
    }

    func add(_ id: ID, keyCode: Int, modifiers: UInt32 = controlOption,
             onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        guard refs[id.rawValue] == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5350_4E54), id: id.rawValue) // 'SPNT'
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id.rawValue] = ref
            pressActions[id.rawValue] = onPress
            releaseActions[id.rawValue] = onRelease
        } else {
            NSLog("Screen Pointer: hotkey \(id.rawValue) is already taken (status \(status))")
        }
    }

    func add(_ id: ID, keyCode: Int, action: @escaping () -> Void) {
        add(id, keyCode: keyCode, onPress: action)
    }

    func remove(_ id: ID) {
        if let ref = refs.removeValue(forKey: id.rawValue) { UnregisterEventHotKey(ref) }
        pressActions[id.rawValue] = nil
        releaseActions[id.rawValue] = nil
    }

    private func fire(_ id: UInt32, released: Bool) {
        (released ? releaseActions[id] : pressActions[id])?()
    }
}

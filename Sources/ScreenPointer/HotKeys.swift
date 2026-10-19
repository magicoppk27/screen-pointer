import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon's RegisterEventHotKey (no permission needed).
///   ⌃⌥C  toggle cursor highlight
///   ⌃⌥K  toggle keystroke overlay
///   ⌃⌥D  toggle draw mode
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    func register() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &handler)

        let controlOption = UInt32(controlKey | optionKey)
        add(1, keyCode: kVK_ANSI_C, modifiers: controlOption) { AppSettings.shared.cursorEnabled.toggle() }
        add(2, keyCode: kVK_ANSI_K, modifiers: controlOption) { AppSettings.shared.keystrokesEnabled.toggle() }
        add(3, keyCode: kVK_ANSI_D, modifiers: controlOption) { DrawController.shared.toggle() }
    }

    private func add(_ id: UInt32, keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5350_4E54), id: id) // 'SPNT'
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            actions[id] = action
        } else {
            NSLog("Screen Pointer: hotkey \(id) is already taken (status \(status))")
        }
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}

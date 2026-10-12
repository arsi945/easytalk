import AppKit
import Carbon.HIToolbox

/// Глобальная горячая клавиша через Carbon RegisterEventHotKey: Accessibility не требуется.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// По умолчанию ⌃⌥Space.
    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            Unmanaged<Hotkey>.fromOpaque(ctx!).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4554_4B59), id: 1)   // 'ETKY'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("easytalk: RegisterEventHotKey failed \(status)") }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

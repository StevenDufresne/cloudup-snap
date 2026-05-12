import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    nonisolated(unsafe) private var ref: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?

    public init() {}

    public func register(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x5343534F), id: 1) // 'SCSO'
        // ⌘⇧2 → keyCode 19 (digit 2 on US layout)
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
    }
}

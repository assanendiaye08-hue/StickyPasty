import Carbon.HIToolbox
import Foundation

// Carbon HotKey manager using a static trampoline pattern.
// C function pointers cannot capture `self`, so we store the instance
// in a static var and reach it from the EventHandler callback.
class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let onPressed: () -> Void

    // Static trampoline — accessed by the C-compatible event handler closure
    nonisolated(unsafe) static var shared: HotKeyManager?

    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed
        HotKeyManager.shared = self
    }

    func register() {
        // Install keyboard event handler on the application event target
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                HotKeyManager.shared?.onPressed()
                return OSStatus(noErr)
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Register Option+Cmd+V
        // kVK_ANSI_V = 0x09 = 9
        // cmdKey = 256, optionKey = 2048  →  combined = 2304
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x53505459),   // 'SPTY' — StickyPasty signature
            id: 1
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if HotKeyManager.shared === self {
            HotKeyManager.shared = nil
        }
    }
}

import CoreGraphics
import AppKit
import Carbon.HIToolbox

enum PasteSimulator {
    /// Simulates Cmd+V keypress to the currently frontmost application.
    /// Requires Accessibility permission (System Settings > Privacy > Accessibility).
    static func simulatePaste() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        let vKeyCode: CGKeyCode = 9   // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

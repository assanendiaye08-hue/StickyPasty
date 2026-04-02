import AppKit
import SwiftUI

/// Borderless, non-activating NSPanel that can still receive keyboard events.
/// This is how Pasty-style clipboard managers work:
///   - The panel floats above all windows but does NOT activate our app
///   - The previous app keeps focus (text cursor stays in its text field)
///   - The panel can still receive keystrokes (search, arrow keys, Enter)
///   - After dismiss, paste works immediately — no focus restoration needed
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class MainPanelController {
    private var panel: NSPanel?
    private let store: ClipboardStore
    private var mouseMonitor: Any?

    /// The app that was frontmost before the panel appeared.
    /// Needed when the panel was opened via menu bar (which activates our app).
    private var previousApp: NSRunningApplication?

    private let panelHeight: CGFloat = 260

    private var panelWidth: CGFloat {
        (NSScreen.main ?? NSScreen.screens.first!).visibleFrame.width
    }

    private var isVisible: Bool {
        panel?.isVisible ?? false
    }

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        DispatchQueue.main.async {
            self.isVisible ? self.hide() : self.show()
        }
    }

    func show() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }

        // Remember the previous app so we can restore focus if needed
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.stickyspasty.app"
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != myBundleID {
            previousApp = frontmost
        }

        if panel == nil { buildPanel() }
        guard let panel else { return }

        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    func hide() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        panel?.orderOut(nil)

        // If our app somehow became active (e.g. opened from menu bar),
        // reactivate the previous app so it gets focus back.
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.stickyspasty.app"
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == myBundleID,
           let prev = previousApp, !prev.isTerminated {
            prev.activate()
        }
    }

    /// Hide the panel, restore focus if needed, then simulate Cmd+V.
    func hideAndPaste() {
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.stickyspasty.app"
        let weAreActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == myBundleID

        hide()

        if !weAreActive {
            // Non-activating panel path (hotkey) — previous app never lost focus.
            // Brief delay to let the panel fully dismiss.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PasteSimulator.simulatePaste()
            }
        } else {
            // Menu bar path — our app was active.  hide() already called activate()
            // on the previous app, but we must wait until it's actually frontmost
            // before injecting Cmd+V.
            let target = previousApp?.bundleIdentifier
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                attempts += 1
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if front == target || front != myBundleID || attempts >= 20 {
                    timer.invalidate()
                    // Extra beat for the target app to restore its first responder
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        PasteSimulator.simulatePaste()
                    }
                }
            }
        }
    }

    // MARK: - Build

    private func buildPanel() {
        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isMovableByWindowBackground = false
        p.isMovable = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true

        let rootView = MainPanelView(store: store, onDismiss: { [weak self] in
            DispatchQueue.main.async { self?.hide() }
        }, onCopyAndPaste: { [weak self] in
            DispatchQueue.main.async { self?.hideAndPaste() }
        })
        p.contentView = NSHostingView(rootView: rootView)
        p.hidesOnDeactivate = false

        panel = p
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.visibleFrame

        let x = sf.minX
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: sf.maxY))
    }
}

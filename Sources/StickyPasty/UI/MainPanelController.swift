import AppKit
import SwiftUI

class MainPanelController {
    private var panel: NSPanel?
    private let store: ClipboardStore
    private var isVisible = false

    private let panelHeight: CGFloat = 260

    private var panelWidth: CGFloat {
        (NSScreen.main ?? NSScreen.screens.first!).visibleFrame.width
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
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // Position BEFORE showing so there is no flicker
        positionPanel(panel)

        panel.orderFrontRegardless()   // show without activating the app
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    // MARK: - Build

    private func buildPanel() {
        // .borderless: no title-bar chrome at all, window frame == content frame exactly.
        // macOS will not cascade or constrain a borderless NSPanel.
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true           // borderless windows need explicit shadow

        let rootView = MainPanelView(store: store, onDismiss: { [weak self] in
            DispatchQueue.main.async { self?.hide() }
        })
        p.contentView = NSHostingView(rootView: rootView)
        p.hidesOnDeactivate = false

        panel = p
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel) {
        // Prefer the screen that currently has keyboard focus (same screen the user is on).
        // Fall back to the primary screen if nothing has focus.
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.visibleFrame   // already excludes the menu bar height

        // Full-width: start at the left edge of the visible frame.
        let x = sf.minX

        // Pin top-left corner to the bottom of the menu bar.
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: sf.maxY))
    }
}

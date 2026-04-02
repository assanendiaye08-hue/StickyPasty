import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {

    // All sub-objects must be held strongly here or they'll be deallocated
    private var statusItem: NSStatusItem!
    private var store: ClipboardStore!
    private var panelController: MainPanelController!
    private var monitor: ClipboardMonitor!
    private var hotKeyManager: HotKeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Data layer
        store = ClipboardStore()

        // 2. UI panel
        panelController = MainPanelController(store: store)

        // 3. Clipboard monitoring
        monitor = ClipboardMonitor(store: store)
        store.clipboardMonitor = monitor
        monitor.start()

        // 4. Global hotkey Option+Cmd+V
        hotKeyManager = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }
        hotKeyManager.register()

        // 5. Menu bar icon
        setupStatusItem()

        // 6. Request Accessibility permission for "Copy & Paste" feature
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyManager.unregister()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "StickyPasty")
            button.image?.isTemplate = true   // auto-inverts for dark/light menu bar
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show History  ⌥⌘V", action: #selector(showPanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAgentManager.isInstalled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit StickyPasty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func toggleLaunchAtLogin() {
        if LaunchAgentManager.isInstalled {
            LaunchAgentManager.uninstall()
        } else {
            LaunchAgentManager.install()
        }
        // Refresh checkmark
        if let menu = statusItem.menu,
           let item = menu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
            item.state = LaunchAgentManager.isInstalled ? .on : .off
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "Pinned items will be kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearHistory()
        }
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - LaunchAgent Manager

enum LaunchAgentManager {
    static let bundleID = "com.stickyspasty.app"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() {
        // Find our own executable path
        let execPath = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments[0]

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(bundleID)</string>
    <key>Program</key>
    <string>\(execPath)</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
"""
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)

        // Load immediately
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(getuid())", plistURL.path]
        try? task.run()
        task.waitUntilExit()
    }

    static func uninstall() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(bundleID)"]
        try? task.run()
        task.waitUntilExit()
        try? FileManager.default.removeItem(at: plistURL)
    }
}

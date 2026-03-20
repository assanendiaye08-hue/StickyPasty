import AppKit

// NSApplication.shared must be called FIRST — NSApp is nil until then.
// setActivationPolicy(.accessory) suppresses the Dock icon.
// LSUIElement=true in Info.plist handles the bundled .app case.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

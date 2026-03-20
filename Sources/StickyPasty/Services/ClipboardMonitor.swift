import AppKit
import Foundation

class ClipboardMonitor {
    private weak var store: ClipboardStore?
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var suppressNext = false

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount

        // Listen for suppress requests from ClipboardItemRow when we write to clipboard ourselves
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSuppress),
            name: .suppressNextCapture,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    @objc private func handleSuppress() {
        suppressNext = true
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if suppressNext {
            suppressNext = false
            return
        }

        // Try image first, then fall back to text
        if let image = NSImage(pasteboard: pb) {
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                // Skip very large images to avoid bloating storage
                guard png.count < 5_000_000 else { return }
                let item = ClipboardItem(
                    id: UUID(),
                    content: .image(png),
                    timestamp: Date(),
                    spaceID: nil
                )
                store?.add(item)
            }
        } else if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let item = ClipboardItem(
                id: UUID(),
                content: .text(text),
                timestamp: Date(),
                spaceID: nil
            )
            store?.add(item)
        }
    }
}

extension Notification.Name {
    static let suppressNextCapture = Notification.Name("StickyPasty.suppressNextCapture")
}

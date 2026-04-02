import AppKit
import os

class ClipboardMonitor {
    private weak var store: ClipboardStore?
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    /// Stores the changeCount to suppress (atomically accessed).
    /// -1 means "nothing to suppress".
    private let suppressedChangeCount = OSAllocatedUnfairLock(initialState: Int(-1))

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        stop()
    }

    func start() {
        // Poll on main thread — NSPasteboard/NSImage are AppKit objects
        // and must be accessed from the main thread. The poll is lightweight
        // (changeCount check + occasional string/image read).
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Suppress a specific changeCount so the monitor skips our own pasteboard write.
    func suppressChangeCount(_ count: Int) {
        suppressedChangeCount.withLock { $0 = count }
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // Check if this changeCount should be suppressed (our own write)
        let suppressed = suppressedChangeCount.withLock { stored -> Bool in
            if count == stored {
                stored = -1
                return true
            }
            return false
        }
        if suppressed { return }

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

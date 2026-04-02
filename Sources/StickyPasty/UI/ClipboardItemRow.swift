import SwiftUI
import AppKit
import Photos

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    let isInSpace: Bool
    var isSelected: Bool = false
    var shortcutNumber: Int? = nil
    let onDismiss: () -> Void
    let onCopyAndPaste: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content preview — text gets padding, images go edge-to-edge
            switch item.content {
            case .text:
                contentPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            case .image:
                contentPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            Divider()

            // Footer: shortcut badge + timestamp
            HStack(spacing: 6) {
                if let n = shortcutNumber {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                }
                Text(item.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if item.spaceID != nil {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 160)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.15)
                      : isHovered
                        ? Color.primary.opacity(0.10)
                        : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected
                              ? Color.accentColor.opacity(0.5)
                              : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { copyAndPaste() }
        .contextMenu { contextMenuContent }
    }

    // MARK: - Content preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let s):
            Text(s)
                .lineLimit(6)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

        case .image(let data):
            if let nsImage = NSImage(data: data) {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .background(Color.primary.opacity(0.04))
                .onDrag {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(
                        forTypeIdentifier: "public.png",
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    return provider
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("Copy") { copyToClipboard() }
        Button("Copy & Paste") { copyAndPaste() }

        if item.isImage {
            Divider()
            Button("Save to Photos") { saveToPhotos() }
            Button("Save to Downloads") { saveToDownloads() }
        }

        Divider()

        if isInSpace {
            Button("Remove from Space") { store.removeFromSpace(item) }
        } else {
            if store.spaces.isEmpty {
                Button("Save to Space...") { promptCreateAndSave() }
            } else {
                Menu("Save to Space") {
                    ForEach(store.spaces.sorted { $0.order < $1.order }) { space in
                        Button(space.name) {
                            store.copyToSpace(item, spaceID: space.id)
                        }
                    }
                }
            }
        }

        Divider()
        Button("Delete", role: .destructive) { store.delete(item) }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        let pb = NSPasteboard.general

        // If the pasteboard already contains this exact text, skip the write.
        // This preserves Handoff metadata and avoids an unnecessary changeCount bump.
        if case .text(let s) = item.content,
           let current = pb.string(forType: .string),
           current == s {
            store.clipboardMonitor?.suppressChangeCount(pb.changeCount)
            return
        }

        pb.clearContents()
        switch item.content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        }
        // Suppress the changeCount we just created — synchronous, no timing window
        store.clipboardMonitor?.suppressChangeCount(pb.changeCount)
    }

    private func copyAndPaste() {
        copyToClipboard()
        onCopyAndPaste()
    }

    private func saveToPhotos() {
        guard case .image(let data) = item.content else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    private func saveToDownloads() {
        guard case .image(let data) = item.content else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dest = downloads.appendingPathComponent("clipboard-\(item.id).png")
        try? data.write(to: dest)
    }

    private func promptCreateAndSave() {
        let alert = NSAlert()
        alert.messageText = "Create a Space"
        alert.informativeText = "Give your first Space a name to save this item."
        alert.addButton(withTitle: "Create & Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        input.placeholderString = "e.g. Work, Personal..."
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let spaceID = store.addSpace(name: name)
                store.copyToSpace(item, spaceID: spaceID)
            }
        }
    }
}

import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    let isInSpace: Bool
    let onDismiss: () -> Void

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

            // Footer: timestamp
            HStack {
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
                .fill(isHovered
                      ? Color.primary.opacity(0.10)
                      : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { copyToClipboard() }
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
        pb.clearContents()
        switch item.content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        }
        NotificationCenter.default.post(name: .suppressNextCapture, object: nil)
    }

    private func copyAndPaste() {
        copyToClipboard()
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteSimulator.simulatePaste()
        }
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
                store.addSpace(name: name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let space = store.spaces.last {
                        store.copyToSpace(item, spaceID: space.id)
                    }
                }
            }
        }
    }
}

import SwiftUI
import AppKit

// Selection state: nil = "All" (history), UUID = specific Space
enum SidebarSelection: Equatable {
    case all
    case space(UUID)
}

struct MainPanelView: View {
    @ObservedObject var store: ClipboardStore
    let onDismiss: () -> Void
    let onCopyAndPaste: () -> Void

    @State private var selection: SidebarSelection = .all
    @State private var selectedIndex: Int = 0
    @State private var isAddingSpace = false
    @State private var newSpaceName = ""
    @FocusState private var newSpaceFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // ── Left Sidebar ─────────────────────────────────────────
            sidebar
                .frame(width: 148)

            // Vertical divider
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)

            // ── Right Content ─────────────────────────────────────────
            VStack(spacing: 0) {
                searchBar
                Divider()
                contentList
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: 260)
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 10,
                bottomTrailingRadius: 10, topTrailingRadius: 0
            )
        )
        .onExitCommand(perform: onDismiss)
        .onAppear { selectedIndex = 0 }
        .onChange(of: selection) { _ in selectedIndex = 0 }
        .onChange(of: store.searchQuery) { _ in selectedIndex = 0 }
        .background(KeyboardHandlerView(onEvent: handleKeyEvent))
    }

    // MARK: - Keyboard navigation

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Don't intercept keystrokes when a text field has focus (search bar, new space name)
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           firstResponder is NSTextView || firstResponder is NSTextField {
            // Still allow arrow keys and Escape when in search — Return submits the field
            let code = Int(event.keyCode)
            if code != 123 && code != 124 { return false }
        }

        let items = currentDisplayItems

        switch Int(event.keyCode) {
        case 123: // Left arrow
            if selectedIndex > 0 { selectedIndex -= 1 }
            return true
        case 124: // Right arrow
            if selectedIndex < items.count - 1 { selectedIndex += 1 }
            return true
        case 36: // Return/Enter — paste selected item
            guard selectedIndex < items.count else { return false }
            let item = items[selectedIndex]
            copyItemToClipboard(item)
            store.bumpToFront(item)
            onCopyAndPaste()
            return true
        case 51: // Delete/Backspace — remove selected item
            guard selectedIndex < items.count else { return false }
            let item = items[selectedIndex]
            store.delete(item)
            if selectedIndex >= items.count - 1 { selectedIndex = max(0, items.count - 2) }
            return true
        default:
            // Cmd+1–9: quick paste nth item
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let digit = chars.first?.wholeNumberValue,
               digit >= 1 && digit <= 9 {
                let idx = digit - 1
                guard idx < items.count else { return false }
                let item = items[idx]
                copyItemToClipboard(item)
                store.bumpToFront(item)
                onCopyAndPaste()
                return true
            }
            return false
        }
    }

    private var currentDisplayItems: [ClipboardItem] {
        switch selection {
        case .all: return store.historyItems
        case .space(let id): return store.items(inSpace: id)
        }
    }

    private func copyItemToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        if case .text(let s) = item.content,
           let current = pb.string(forType: .string),
           current == s {
            store.clipboardMonitor?.suppressChangeCount(pb.changeCount)
            return
        }
        pb.clearContents()
        switch item.content {
        case .text(let s): pb.setString(s, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) { pb.writeObjects([image]) }
        }
        store.clipboardMonitor?.suppressChangeCount(pb.changeCount)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App title
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("StickyPasty")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 0)

            ScrollView {
                VStack(spacing: 2) {
                    // "All" row
                    SidebarRow(
                        icon: "clock.arrow.circlepath",
                        label: "All",
                        count: store.historyItems.count,
                        color: .blue,
                        isSelected: selection == .all
                    )
                    .onTapGesture { selection = .all }

                    if !store.spaces.isEmpty {
                        Divider()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        ForEach(store.spaces.sorted { $0.order < $1.order }) { space in
                            SidebarRow(
                                icon: "folder.fill",
                                label: space.name,
                                count: store.count(inSpace: space.id),
                                color: Color(nsColor: space.color),
                                isSelected: selection == .space(space.id)
                            )
                            .onTapGesture { selection = .space(space.id) }
                            .contextMenu {
                                Button("Rename Space") { beginRename(space) }
                                Divider()
                                Button("Delete Space", role: .destructive) {
                                    if case .space(let id) = selection, id == space.id {
                                        selection = .all
                                    }
                                    store.deleteSpace(space)
                                }
                            }
                        }
                    }

                    // Inline new-space text field
                    if isAddingSpace {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            TextField("Space name", text: $newSpaceName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .focused($newSpaceFieldFocused)
                                .onSubmit { commitNewSpace() }
                                .onExitCommand { cancelNewSpace() }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)

            Divider()

            // "+" Add Space button
            Button(action: beginAddingSpace) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Space")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
            TextField("Search...", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !store.searchQuery.isEmpty {
                Button(action: { store.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Content list

    @ViewBuilder
    private var contentList: some View {
        let displayItems = currentDisplayItems

        let emptyMessage: String = {
            if !store.searchQuery.isEmpty { return "No results" }
            switch selection {
            case .all: return "Nothing copied yet"
            case .space: return "No items in this space yet\nDrag items here or use right-click"
            }
        }()

        if displayItems.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: selection == .all ? "tray" : "folder")
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemRow(
                                item: item,
                                store: store,
                                isInSpace: selection != .all,
                                isSelected: index == selectedIndex,
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                onDismiss: onDismiss,
                                onCopyAndPaste: onCopyAndPaste
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: selectedIndex) { newIndex in
                    if newIndex < displayItems.count {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(displayItems[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Space management helpers

    private func beginAddingSpace() {
        isAddingSpace = true
        newSpaceName = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            newSpaceFieldFocused = true
        }
    }

    private func commitNewSpace() {
        let name = newSpaceName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let spaceID = store.addSpace(name: name)
            selection = .space(spaceID)
        }
        isAddingSpace = false
        newSpaceName = ""
    }

    private func cancelNewSpace() {
        isAddingSpace = false
        newSpaceName = ""
    }

    private func beginRename(_ space: Space) {
        // Use NSAlert for rename — simple, no additional state needed
        let alert = NSAlert()
        alert.messageText = "Rename Space"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        input.stringValue = space.name
        input.placeholderString = "Space name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { store.renameSpace(space, to: name) }
        }
    }
}

// MARK: - Keyboard handler (macOS 13 compatible)

/// Installs a local NSEvent monitor for keyDown events.
/// Returns the event unchanged if the handler doesn't consume it.
private struct KeyboardHandlerView: NSViewRepresentable {
    let onEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherView)?.onEvent = onEvent
    }

    private class KeyCatcherView: NSView {
        var onEvent: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if self?.onEvent?(event) == true { return nil }  // consumed
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            super.removeFromSuperview()
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : color)
                .frame(width: 14, alignment: .center)

            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isSelected
                            ? Color.white.opacity(0.25)
                            : Color.primary.opacity(0.08),
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ? color :
                    isHovered  ? Color.primary.opacity(0.06) :
                    Color.clear
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

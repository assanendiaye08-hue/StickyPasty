import SwiftUI

// Selection state: nil = "All" (history), UUID = specific Space
enum SidebarSelection: Equatable {
    case all
    case space(UUID)
}

struct MainPanelView: View {
    @ObservedObject var store: ClipboardStore
    let onDismiss: () -> Void

    @State private var selection: SidebarSelection = .all
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
        let displayItems: [ClipboardItem] = {
            switch selection {
            case .all: return store.historyItems
            case .space(let id): return store.items(inSpace: id)
            }
        }()

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
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(displayItems) { item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isInSpace: selection != .all,
                            onDismiss: onDismiss
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
            store.addSpace(name: name)
            // Auto-select the new space
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let newSpace = store.spaces.last {
                    selection = .space(newSpace.id)
                }
            }
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

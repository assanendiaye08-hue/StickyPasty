import Foundation
import Combine

class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var spaces: [Space] = []
    @Published var searchQuery: String = ""

    /// Set by AppDelegate after ClipboardMonitor is created.
    /// Used by UI to suppress clipboard captures directly instead of via NotificationCenter.
    weak var clipboardMonitor: ClipboardMonitor?

    private let itemsURL: URL
    private let spacesURL: URL
    private let maxItems = 500
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed views

    /// Clipboard history: items not saved to any Space
    var historyItems: [ClipboardItem] {
        let all = items.filter { $0.spaceID == nil }
        guard !searchQuery.isEmpty else { return all }
        return all.filter { item in
            if case .text(let s) = item.content {
                return s.localizedCaseInsensitiveContains(searchQuery)
            }
            return false   // images have no searchable text
        }
    }

    /// Items saved in a given Space
    func items(inSpace spaceID: UUID) -> [ClipboardItem] {
        let all = items.filter { $0.spaceID == spaceID }
        guard !searchQuery.isEmpty else { return all }
        return all.filter { item in
            if case .text(let s) = item.content {
                return s.localizedCaseInsensitiveContains(searchQuery)
            }
            return false   // images have no searchable text
        }
    }

    func count(inSpace spaceID: UUID) -> Int {
        items.filter { $0.spaceID == spaceID }.count
    }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("StickyPasty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        itemsURL  = dir.appendingPathComponent("history.json")
        spacesURL = dir.appendingPathComponent("spaces.json")
        load()

        // Debounced auto-save — debounce on main (safe to read @Published),
        // then dispatch file I/O to background with data already captured.
        $items
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] currentItems in self?.saveItems(currentItems) }
            .store(in: &cancellables)

        $spaces
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] currentSpaces in self?.saveSpaces(currentSpaces) }
            .store(in: &cancellables)
    }

    // MARK: - Clipboard item CRUD

    func add(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            // Deduplicate identical text in history (not in spaces)
            if case .text(let newText) = item.content {
                self.items.removeAll { existing in
                    if case .text(let t) = existing.content {
                        return t == newText && existing.spaceID == nil
                    }
                    return false
                }
            }
            self.items.insert(item, at: 0)
            // Trim history — never evict Space items
            if self.items.count > self.maxItems {
                var kept: [ClipboardItem] = []
                var historyCount = 0
                for i in self.items {
                    if i.spaceID != nil {
                        kept.append(i)
                    } else if historyCount < self.maxItems {
                        kept.append(i)
                        historyCount += 1
                    }
                }
                self.items = kept
            }
        }
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearHistory() {
        items.removeAll { $0.spaceID == nil }
    }

    // MARK: - Space assignment

    func addToSpace(_ item: ClipboardItem, spaceID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].spaceID = spaceID
    }

    func removeFromSpace(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].spaceID = nil
    }

    /// Copy an item into a space without removing it from history
    func copyToSpace(_ item: ClipboardItem, spaceID: UUID) {
        let copy = ClipboardItem(
            id: UUID(),
            content: item.content,
            timestamp: item.timestamp,
            spaceID: spaceID
        )
        items.append(copy)
    }

    // MARK: - Space CRUD

    @discardableResult
    func addSpace(name: String) -> UUID {
        let colorIndex = spaces.count % Space.presetColors.count
        let space = Space(
            id: UUID(),
            name: name,
            colorHex: Space.presetColors[colorIndex],
            order: spaces.count
        )
        spaces.append(space)
        return space.id
    }

    func renameSpace(_ space: Space, to name: String) {
        guard let idx = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[idx].name = name
    }

    func deleteSpace(_ space: Space) {
        for idx in items.indices where items[idx].spaceID == space.id {
            items[idx].spaceID = nil
        }
        spaces.removeAll { $0.id == space.id }
    }

    // MARK: - Private

    private func load() {
        if let data = try? Data(contentsOf: itemsURL),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        }
        if let data = try? Data(contentsOf: spacesURL),
           let decoded = try? JSONDecoder().decode([Space].self, from: data) {
            spaces = decoded
        }
    }

    private func saveItems(_ itemsToSave: [ClipboardItem]) {
        guard let data = try? JSONEncoder().encode(itemsToSave) else { return }
        try? data.write(to: itemsURL, options: .atomic)
    }

    private func saveSpaces(_ spacesToSave: [Space]) {
        guard let data = try? JSONEncoder().encode(spacesToSave) else { return }
        try? data.write(to: spacesURL, options: .atomic)
    }
}

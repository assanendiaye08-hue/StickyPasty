import Foundation
import Combine

class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var spaces: [Space] = []
    @Published var searchQuery: String = ""

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
            return searchQuery.isEmpty   // images only show when no search
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
            return false
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

        // Debounced auto-save
        $items
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in self?.saveItems() }
            .store(in: &cancellables)

        $spaces
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in self?.saveSpaces() }
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
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == item.id }
        }
    }

    func clearHistory() {
        DispatchQueue.main.async {
            self.items.removeAll { $0.spaceID == nil }
        }
    }

    // MARK: - Space assignment

    func addToSpace(_ item: ClipboardItem, spaceID: UUID) {
        // Remove from history (or current space) and place into target space
        updateItem(id: item.id) { $0.spaceID = spaceID }
    }

    func removeFromSpace(_ item: ClipboardItem) {
        // Move back to history
        updateItem(id: item.id) { $0.spaceID = nil }
    }

    /// Copy an item into a space without removing it from history
    func copyToSpace(_ item: ClipboardItem, spaceID: UUID) {
        DispatchQueue.main.async {
            let copy = ClipboardItem(
                id: UUID(),
                content: item.content,
                timestamp: item.timestamp,
                spaceID: spaceID
            )
            self.items.append(copy)
        }
    }

    // MARK: - Space CRUD

    func addSpace(name: String) {
        DispatchQueue.main.async {
            let colorIndex = self.spaces.count % Space.presetColors.count
            let space = Space(
                id: UUID(),
                name: name,
                colorHex: Space.presetColors[colorIndex],
                order: self.spaces.count
            )
            self.spaces.append(space)
        }
    }

    func renameSpace(_ space: Space, to name: String) {
        DispatchQueue.main.async {
            guard let idx = self.spaces.firstIndex(where: { $0.id == space.id }) else { return }
            self.spaces[idx].name = name
        }
    }

    func deleteSpace(_ space: Space) {
        DispatchQueue.main.async {
            // Move all items from this space back to history
            for idx in self.items.indices where self.items[idx].spaceID == space.id {
                self.items[idx].spaceID = nil
            }
            self.spaces.removeAll { $0.id == space.id }
        }
    }

    // MARK: - Private

    private func updateItem(id: UUID, transform: @escaping (inout ClipboardItem) -> Void) {
        DispatchQueue.main.async {
            guard let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
            transform(&self.items[idx])
        }
    }

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

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: itemsURL, options: .atomic)
    }

    private func saveSpaces() {
        guard let data = try? JSONEncoder().encode(spaces) else { return }
        try? data.write(to: spacesURL, options: .atomic)
    }
}

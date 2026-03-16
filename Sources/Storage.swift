import Foundation

@MainActor
class Storage: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var folders: [AppFolder] = []
    
    // Preferences
    @Published var sortOption: SortOption = .newest
    @Published var spawnAtCursor: Bool = true
    @Published var selectedFolderID: UUID? = nil
    
    private let fileManager = FileManager.default
    private var documentDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SkyPaste")
    }
    private var dataFile: URL? {
        documentDirectory?.appendingPathComponent("history.json")
    }
    
    // Debounce: don't hit disk on every keystroke / rapid copies
    private var saveWorkItem: DispatchWorkItem?
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveItems() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    
    init() {
        setupDirectory()
        loadItems()
        loadFolders()
    }
    
    private func setupDirectory() {
        guard let dir = documentDirectory else { return }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        let maxItems = 500
        // Deduplicate plain text
        if item.type == .text, let t = item.textContent, let index = items.firstIndex(where: { $0.textContent == t }) {
            var existing = items[index]
            existing.timestamp = Date()
            existing.copyCount = (existing.copyCount ?? 1) + 1
            items.remove(at: index)
            if existing.isPinned {
                items.insert(existing, at: index)
            } else {
                items.insert(existing, at: 0)
            }
            scheduleSave()
            return
        }
        
        items.insert(item, at: 0)
        enforceQuotas()
        
        // Hard cap: evict oldest unpinned items beyond limit
        while items.filter({ !$0.isPinned }).count > maxItems {
            if let lastIdx = items.lastIndex(where: { !$0.isPinned }) {
                let old = items[lastIdx]
                if let url = old.fileURL, url.path.contains("SkyPaste/Images") {
                    try? fileManager.removeItem(at: url)
                    ImageCache.shared.removeImage(for: url)
                }
                items.remove(at: lastIdx)
            } else { break }
        }
        
        scheduleSave()
    }
    
    func clearUnpinned() {
        let toDelete = items.filter { !$0.isPinned && $0.folderID == nil }
        for item in toDelete {
            if let url = item.fileURL, url.path.contains("SkyPaste/Images") {
                try? fileManager.removeItem(at: url)
                ImageCache.shared.removeImage(for: url)
            }
        }
        items.removeAll { !$0.isPinned && $0.folderID == nil }
        saveItems()
    }
    
    func clearUnpinnedText() {
        items.removeAll { !$0.isPinned && $0.type == .text && $0.folderID == nil }
        saveItems()
    }
    
    func createFolder(name: String, emoji: String? = nil, colorHex: String? = nil) {
        let folder = AppFolder(name: name, emoji: emoji, colorHex: colorHex)
        folders.append(folder)
        saveFolders()
    }
    
    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        // Remove items from this folder
        for i in 0..<items.count {
            if items[i].folderID == id { items[i].folderID = nil }
        }
        saveItems()
        saveFolders()
    }
    
    func clearFolder(id: UUID) {
        let toDelete = items.filter { $0.folderID == id }
        for item in toDelete {
            if let url = item.fileURL, url.path.contains("SkyPaste/Images") {
                try? fileManager.removeItem(at: url)
                ImageCache.shared.removeImage(for: url)
            }
        }
        items.removeAll { $0.folderID == id }
        saveItems()
    }
    
    func updateFolder(_ folder: AppFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            saveFolders()
        }
    }
    
    func assign(item id: UUID, to folderID: UUID?) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].folderID = folderID
            saveItems()
        }
    }
    
    func togglePin(for id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isPinned.toggle()
            if items[index].isPinned {
                // Determine next pin order
                let nextOrder = items.filter { $0.isPinned }.map { $0.pinnedOrder }.min() ?? 0
                items[index].pinnedOrder = nextOrder - 1
            }
            saveItems()
        }
    }
    
    func movePinned(source: IndexSet, destination: Int) {
        let pinnedItems = items.filter { $0.isPinned }.sorted { $0.pinnedOrder < $1.pinnedOrder }
        var reordered = pinnedItems
        reordered.move(fromOffsets: source, toOffset: destination)
        
        for (i, item) in reordered.enumerated() {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].pinnedOrder = i
            }
        }
        saveItems()
    }
    
    func deleteItem(with id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items[index]
            if let url = item.fileURL, url.path.contains("SkyPaste/Images") {
                try? fileManager.removeItem(at: url)
                ImageCache.shared.removeImage(for: url)
            }
            items.remove(at: index)
            saveItems()
        }
    }
    
    func moveToTop(for id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            var updatedItem = items[index]
            updatedItem.timestamp = Date()
            items.remove(at: index)
            items.insert(updatedItem, at: 0)
            saveItems()
        }
    }
    
    private func enforceQuotas() {
        let defaults = UserDefaults.standard
        let neverDelete = defaults.bool(forKey: "neverDelete")
        if neverDelete { return }
        
        let retainDays = defaults.integer(forKey: "retainDays")
        let limitMB = defaults.double(forKey: "cacheLimitMB")
        
        if retainDays > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -retainDays, to: Date())!
            let toDelete = items.filter { !$0.isPinned && $0.timestamp < cutoff }
            for item in toDelete {
                if let url = item.fileURL, url.path.contains("SkyPaste/Images") { 
                    try? fileManager.removeItem(at: url)
                    ImageCache.shared.removeImage(for: url)
                }
            }
            items.removeAll { !$0.isPinned && $0.timestamp < cutoff }
        }
        
        if limitMB > 0 {
            var currentSize: Double = 0
            for item in items {
                if let url = item.fileURL, url.path.contains("SkyPaste/Images"), let attr = try? fileManager.attributesOfItem(atPath: url.path), let size = attr[.size] as? Double {
                    currentSize += size / (1024 * 1024)
                }
            }
            
            while currentSize > limitMB, let lastUnpinned = items.lastIndex(where: { !$0.isPinned }) {
                let item = items[lastUnpinned]
                if let url = item.fileURL, url.path.contains("SkyPaste/Images"), let attr = try? fileManager.attributesOfItem(atPath: url.path), let size = attr[.size] as? Double {
                    currentSize -= size / (1024 * 1024)
                    try? fileManager.removeItem(at: url)
                    ImageCache.shared.removeImage(for: url)
                }
                items.remove(at: lastUnpinned)
            }
        }
    }
    
    private func loadItems() {
        guard let url = dataFile, let data = try? Data(contentsOf: url) else { return }
        do {
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    private func saveItems() {
        guard let url = dataFile else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    private var foldersFile: URL? {
        documentDirectory?.appendingPathComponent("folders.json")
    }
    
    private func loadFolders() {
        guard let url = foldersFile, let data = try? Data(contentsOf: url) else { return }
        do {
            folders = try JSONDecoder().decode([AppFolder].self, from: data)
        } catch {}
    }
    
    private func saveFolders() {
        guard let url = foldersFile, let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: url)
    }
}

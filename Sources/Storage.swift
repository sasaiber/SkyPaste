import Foundation
import ServiceManagement
import AppKit

@MainActor
class Storage: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var folders: [AppFolder] = []
    
    // Popover inner state for shortcuts
    @Published var popoverSelectedURLs: [URL] = []
    @Published var popoverHoveredURL: URL? = nil
    
    // Cached folder item counts (updated when items change)
    private var folderItemCountCache: [UUID: Int] = [:]
    
    func itemCount(forFolderID folderID: UUID) -> Int {
        if let cached = folderItemCountCache[folderID] { return cached }
        let count = items.filter { $0.folderID == folderID }.count
        folderItemCountCache[folderID] = count
        return count
    }
    
    private func invalidateFolderCountCache() {
        folderItemCountCache.removeAll()
    }
    
    // Preferences
    @Published var sortOption: SortOption = .newest
    @Published var spawnAtCursor: Bool = true
    @Published var selectedFolderID: UUID? = nil
    @Published var hoveredItemID: UUID? = nil
    
    // Toast notification for folder move feedback
    @Published var folderMoveToast: (folder: AppFolder, shortcut: String?)? = nil
    
    func showFolderMoveToast(folder: AppFolder, shortcut: String? = nil) {
        folderMoveToast = (folder, shortcut)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            folderMoveToast = nil
        }
    }
    
    // Global Shortcut Helpers
    func getFolderShortcut(folderID: UUID, type: String) -> (key: String, mod: Int)? {
        let keyStr = type == "open" ? "folderShortcuts" : "folderMoveShortcuts"
        if let data = UserDefaults.standard.data(forKey: keyStr),
           let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data),
           let found = decoded.first(where: { $0.folderID == folderID }) {
            return (found.keyText, found.modifiers)
        }
        return nil
    }
    
    func saveFolderShortcut(folderID: UUID, type: String, key: String, mod: Int) {
        let keyStr = type == "open" ? "folderShortcuts" : "folderMoveShortcuts"
        let defaults = UserDefaults.standard
        var array: [HotkeyManager.FolderShortcut] = []
        if let data = defaults.data(forKey: keyStr),
           let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
            array = decoded
        }
        array.removeAll { $0.folderID == folderID }
        if !key.isEmpty {
            array.append(HotkeyManager.FolderShortcut(folderID: folderID, keyText: key, modifiers: mod))
        }
        if let newData = try? JSONEncoder().encode(array) {
            defaults.set(newData, forKey: keyStr)
        }
        DispatchQueue.main.async { HotkeyManager.shared.start() }
    }
    
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
        invalidateFolderCountCache()
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
        
        // Deduplicate images by comparing textContent (contains all image URLs)
        if item.type == .image, let content = item.textContent, !content.isEmpty {
            if let index = items.firstIndex(where: { $0.type == .image && $0.textContent == content }) {
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
        }
        
        // Deduplicate files by comparing textContent (contains all file URLs)
        if item.type == .file, let content = item.textContent, !content.isEmpty {
            if let index = items.firstIndex(where: { $0.type == .file && $0.textContent == content }) {
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
        }
        
        // Deduplicate links
        if item.type == .link, let link = item.textContent, !link.isEmpty {
            if let index = items.firstIndex(where: { $0.type == .link && $0.textContent == link }) {
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
        invalidateFolderCountCache()
        let toDelete = items.filter { !$0.isPinned && $0.folderID == nil }
        for item in toDelete {
            if let url = item.fileURL, url.path.contains("SkyPaste/Images") {
                try? fileManager.removeItem(at: url)
                ImageCache.shared.removeImage(for: url)
            }
        }
        items.removeAll { !$0.isPinned && $0.folderID == nil }
        saveItems()
        NSPasteboard.general.clearContents()
    }
    
    func clearUnpinnedText(folderID: UUID? = nil) {
        invalidateFolderCountCache()
        if let folderID = folderID {
            // Clear text items only in this folder
            items.removeAll { !$0.isPinned && $0.type == .text && $0.folderID == folderID }
        } else {
            // Clear all text items globally (no folder)
            items.removeAll { !$0.isPinned && $0.type == .text && $0.folderID == nil }
        }
        saveItems()
        NSPasteboard.general.clearContents()
    }
    
    func factoryReset() {
        // Remove from login items
        SMAppService.mainApp.unregisterSafe()
        
        // Clear all files
        if let dir = documentDirectory {
            try? fileManager.removeItem(at: dir)
        }
        
        // Wipe UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
        
        // Terminate the app completely
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
    
    func createFolder(name: String, emoji: String? = nil, colorHex: String? = nil, appBundleIDs: [String] = []) {
        var folder = AppFolder(name: name, emoji: emoji, colorHex: colorHex, order: folders.count)
        folder.appBundleIDs = appBundleIDs
        folders.append(folder)
        saveFolders()
    }
    
    func reorderFolders(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        for i in folders.indices {
            folders[i].order = i
        }
        saveFolders()
    }
    
    func updateFolderAppBindings(id: UUID, bundleIDs: [String]) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].appBundleIDs = bundleIDs
            saveFolders()
        }
    }
    
    func deleteFolder(id: UUID) {
        invalidateFolderCountCache()
        folders.removeAll { $0.id == id }
        // Remove items from this folder
        for i in 0..<items.count {
            if items[i].folderID == id { items[i].folderID = nil }
        }
        saveItems()
        saveFolders()
        
        // Clean up shortcuts to prevent ghost shortcuts
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "folderShortcuts"),
           var decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
            decoded.removeAll { $0.folderID == id }
            if let newData = try? JSONEncoder().encode(decoded) {
                defaults.set(newData, forKey: "folderShortcuts")
            }
        }
        
        if let data = defaults.data(forKey: "folderMoveShortcuts"),
           var decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
            decoded.removeAll { $0.folderID == id }
            if let newData = try? JSONEncoder().encode(decoded) {
                defaults.set(newData, forKey: "folderMoveShortcuts")
            }
        }
        
        // Force hotkey manager to unregister removed keys
        DispatchQueue.main.async {
            HotkeyManager.shared.start()
        }
    }
    
    func clearFolder(id: UUID) {
        invalidateFolderCountCache()
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
        invalidateFolderCountCache()
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].folderID = folderID
            saveItems()
            
            if let folderID = folderID, let folder = folders.first(where: { $0.id == folderID }) {
                let shortcut = getFolderShortcut(folderID: folderID, type: "move").map { formatShortcut(key: $0.key, modifiers: $0.mod) }
                showFolderMoveToast(folder: folder, shortcut: shortcut)
            }
        }
    }
    
    private func formatShortcut(key: String, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var str = ""
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }
        return str + key.uppercased()
    }
    
    func togglePin(for id: UUID) {
        invalidateFolderCountCache()
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
        invalidateFolderCountCache()
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
        invalidateFolderCountCache()
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items[index]
            if let url = item.fileURL, url.path.contains("SkyPaste/Images") {
                try? fileManager.removeItem(at: url)
                ImageCache.shared.removeImage(for: url)
            }
            items.remove(at: index)
            saveItems()
            NSPasteboard.general.clearContents()
        }
    }
    
    func deleteFiles(urlsToDelete: [URL], from itemID: UUID) {
        invalidateFolderCountCache()
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            var updatedItem = items[index]
            let oldContent = updatedItem.textContent ?? ""
            var remainingURLs = oldContent.components(separatedBy: "\n").filter { !$0.isEmpty }.compactMap { URL(string: $0) ?? URL(fileURLWithPath: $0) }
            
            remainingURLs.removeAll { urlsToDelete.contains($0) }
            
            if remainingURLs.isEmpty {
                deleteItem(with: itemID)
            } else {
                updatedItem.textContent = remainingURLs.map { $0.absoluteString }.joined(separator: "\n")
                updatedItem.title = remainingURLs.count > 1 ? "\(remainingURLs.count) files" : remainingURLs.first?.lastPathComponent
                updatedItem.fileURL = remainingURLs.first
                updatedItem.fileCount = remainingURLs.count
                items[index] = updatedItem
                saveItems()
            }
            popoverSelectedURLs.removeAll { urlsToDelete.contains($0) }
            if let hovered = popoverHoveredURL, urlsToDelete.contains(hovered) { popoverHoveredURL = nil }
        }
    }
    
    func moveToTop(for id: UUID) {
        invalidateFolderCountCache()
        if let index = items.firstIndex(where: { $0.id == id }) {
            var updatedItem = items[index]
            updatedItem.timestamp = Date()
            items.remove(at: index)
            items.insert(updatedItem, at: 0)
            saveItems()
        }
    }
    
    private func enforceQuotas() {
        invalidateFolderCountCache()
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
            invalidateFolderCountCache()
        } catch {
            // Failed to load history
        }
    }
    
    private func saveItems() {
        guard let url = dataFile else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url)
        } catch {
            // Failed to save history
        }
    }
    
    private var foldersFile: URL? {
        documentDirectory?.appendingPathComponent("folders.json")
    }
    
    private func loadFolders() {
        guard let url = foldersFile, let data = try? Data(contentsOf: url) else { return }
        do {
            var loaded = try JSONDecoder().decode([AppFolder].self, from: data)
            loaded.sort { $0.order < $1.order }
            folders = loaded
        } catch {}
    }
    
    private func saveFolders() {
        guard let url = foldersFile, let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: url)
    }
}

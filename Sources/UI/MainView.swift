import SwiftUI
import AppKit
import UniformTypeIdentifiers

class PreviewWindowManager {
    static let shared = PreviewWindowManager()
    var window: NSWindow?
    
    func show(url: URL) {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isReleasedWhenClosed = false
            win.center()
            self.window = win
        }
        guard let img = NSImage(contentsOf: url) else { return }
        
        let view = ZStack {
            Color.black.ignoresSafeArea()
            Image(nsImage: img).resizable().scaledToFit().padding()
        }.onTapGesture {
            self.window?.close()
        }
        
        window?.contentView = NSHostingView(rootView: view)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private let qwertyToCyrillic: [Character: Character] = [
    "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
    "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д",
    "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю",
]

struct MainView: View {
    @ObservedObject var storage: Storage
    @State private var searchText = ""
    @State private var keyMonitor: Any? = nil
    @State private var itemToAssignToNewFolder: UUID?
    
    @State private var showingFolderSettings = false
    @State private var editingFolderInMain: AppFolder? = nil
    
    @State private var urlsToExtractToNewFolder: [URL]? = nil
    @State private var itemToExtractFrom: ClipboardItem? = nil
    
    @State private var showingTrashAlert = false
    @State private var showingFolderTrashAlert = false
    @State private var currentWindowHeight: CGFloat = 520
    
    @AppStorage("disableMediaPreviews") private var disableMediaPreviews: Bool = false
    @AppStorage("unlimitedMediaPreviews") private var unlimitedMediaPreviews: Bool = true
    @AppStorage("maxPreviewsLimit") private var maxPreviewsLimit: Int = 10
    @AppStorage("suppressGlobalTrashWarning") private var suppressGlobalTrashWarning: Bool = false

    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "f"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFinderKey") private var hkFinderKey: String = "f"
    @AppStorage("hkFinderModifiers") private var hkFinderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    @AppStorage("autoPasteActive") private var autoPasteActive: Bool = true
    @AppStorage("pastePlainActive") private var pastePlainActive: Bool = false
    
    private func eventModifiers(from nsEventFlags: Int) -> EventModifiers {
        var eventMods = EventModifiers()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(nsEventFlags))
        if flags.contains(.command) { eventMods.insert(.command) }
        if flags.contains(.control) { eventMods.insert(.control) }
        if flags.contains(.option) { eventMods.insert(.option) }
        if flags.contains(.shift) { eventMods.insert(.shift) }
        return eventMods
    }
    
    var filteredItems: [ClipboardItem] {
        var result = storage.items
        if let fid = storage.selectedFolderID {
            result = result.filter { $0.folderID == fid }
        } else {
            result = result.filter { $0.folderID == nil }
        }
        if !searchText.isEmpty {
            result = result.filter { ($0.textContent ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        if storage.sortOption == .oldest {
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if $0.isPinned { return $0.pinnedOrder < $1.pinnedOrder }
                return $0.timestamp < $1.timestamp
            }
        } else {
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if $0.isPinned { return $0.pinnedOrder < $1.pinnedOrder }
                return $0.timestamp > $1.timestamp
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if let activeFolder = storage.folders.first(where: { $0.id == storage.selectedFolderID }) {
                folderHeader(activeFolder)
                Divider()
            }
            
            searchBar
            
            Group {
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }.keyboardShortcut("q", modifiers: .command)
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }.keyboardShortcut("й", modifiers: .command)
                
                if let pinChar = hkPinKey.lowercased().first {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        if !selectedURLs.isEmpty, let baseItem = storage.items.first(where: { $0.id == id }) {
                            var newItem = ClipboardItem(
                                timestamp: Date(),
                                firstCopiedAt: Date(),
                                type: baseItem.type,
                                textContent: selectedURLs.map { $0.absoluteString }.joined(separator: "\n"),
                                title: selectedURLs.count > 1 ? "\(selectedURLs.count) files" : selectedURLs.first?.lastPathComponent,
                                fileURL: selectedURLs.first,
                                appSource: baseItem.appSource,
                                appBundleID: baseItem.appBundleID,
                                extensions: baseItem.extensions,
                                fileCount: selectedURLs.count
                            )
                            newItem.isPinned = true
                            withAnimation(.smoothSpring) { storage.addItem(newItem) }
                        } else {
                            withAnimation(.smoothSpring) { storage.togglePin(for: id) }
                        }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(pinChar), modifiers: eventModifiers(from: hkPinModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[pinChar] {
                        Button(action: {
                            guard let id = storage.hoveredItemID else { return }
                            let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                            if !selectedURLs.isEmpty, let baseItem = storage.items.first(where: { $0.id == id }) {
                                var newItem = ClipboardItem(
                                    timestamp: Date(),
                                    firstCopiedAt: Date(),
                                    type: baseItem.type,
                                    textContent: selectedURLs.map { $0.absoluteString }.joined(separator: "\n"),
                                    title: selectedURLs.count > 1 ? "\(selectedURLs.count) files" : selectedURLs.first?.lastPathComponent,
                                    fileURL: selectedURLs.first,
                                    appSource: baseItem.appSource,
                                    appBundleID: baseItem.appBundleID,
                                    extensions: baseItem.extensions,
                                    fileCount: selectedURLs.count
                                )
                                newItem.isPinned = true
                                withAnimation(.smoothSpring) { storage.addItem(newItem) }
                            } else {
                                withAnimation(.smoothSpring) { storage.togglePin(for: id) }
                            }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkPinModifiers))
                    }
                }
            }
            .frame(width: 0, height: 0).opacity(0)
            
            Group {
                if hkDeleteKey.lowercased() == "delete" {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        if !selectedURLs.isEmpty {
                            withAnimation(.easeOut(duration: 0.2)) { storage.deleteFiles(urlsToDelete: selectedURLs, from: id) }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { storage.deleteItem(with: id) }
                        }
                    }) { EmptyView() }
                        .keyboardShortcut(.delete, modifiers: eventModifiers(from: hkDeleteModifiers))
                } else if let deleteChar = hkDeleteKey.lowercased().first {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        if !selectedURLs.isEmpty {
                            withAnimation(.easeOut(duration: 0.2)) { storage.deleteFiles(urlsToDelete: selectedURLs, from: id) }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { storage.deleteItem(with: id) }
                        }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(deleteChar), modifiers: eventModifiers(from: hkDeleteModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[deleteChar] {
                        Button(action: {
                            guard let id = storage.hoveredItemID else { return }
                            let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                            if !selectedURLs.isEmpty {
                                withAnimation(.easeOut(duration: 0.2)) { storage.deleteFiles(urlsToDelete: selectedURLs, from: id) }
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) { storage.deleteItem(with: id) }
                            }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkDeleteModifiers))
                    }
                }
                
                if let folderChar = hkFolderKey.lowercased().first {
                    Button(action: {
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        if !selectedURLs.isEmpty, let id = storage.hoveredItemID, let baseItem = storage.items.first(where: { $0.id == id }) {
                            urlsToExtractToNewFolder = selectedURLs
                            itemToExtractFrom = baseItem
                        } else {
                            itemToAssignToNewFolder = storage.hoveredItemID
                        }
                        storage.hoveredItemID = nil
                        editingFolderInMain = nil
                        showingFolderSettings = true
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(folderChar), modifiers: eventModifiers(from: hkFolderModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[folderChar] {
                        Button(action: {
                            let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                            if !selectedURLs.isEmpty, let id = storage.hoveredItemID, let baseItem = storage.items.first(where: { $0.id == id }) {
                                urlsToExtractToNewFolder = selectedURLs
                                itemToExtractFrom = baseItem
                            } else {
                                itemToAssignToNewFolder = storage.hoveredItemID
                            }
                            storage.hoveredItemID = nil
                            editingFolderInMain = nil
                            showingFolderSettings = true
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkFolderModifiers))
                    }
                }
                
                if let finderChar = hkFinderKey.lowercased().first {
                    Button(action: {
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        let urlsToActOn = selectedURLs.isEmpty ? (storage.items.first(where: { $0.id == storage.hoveredItemID })?.fileURL.map { [$0] } ?? []) : selectedURLs
                        for u in urlsToActOn {
                            NSWorkspace.shared.activateFileViewerSelecting([u])
                        }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(finderChar), modifiers: eventModifiers(from: hkFinderModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[finderChar] {
                        Button(action: {
                            let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                            let urlsToActOn = selectedURLs.isEmpty ? (storage.items.first(where: { $0.id == storage.hoveredItemID })?.fileURL.map { [$0] } ?? []) : selectedURLs
                            for u in urlsToActOn {
                                NSWorkspace.shared.activateFileViewerSelecting([u])
                            }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkFinderModifiers))
                    }
                }
            }
            .frame(width: 0, height: 0).opacity(0)
            
            Divider()
            
            clipboardList
        }
        .frame(width: 400, height: currentWindowHeight, alignment: .top)
        .glassBackground(cornerRadius: 16)
        .edgesIgnoringSafeArea(.all)
        .onExitCommand {
            if showingFolderSettings {
                showingFolderSettings = false
                editingFolderInMain = nil
                itemToAssignToNewFolder = nil
                urlsToExtractToNewFolder = nil
                itemToExtractFrom = nil
            } else {
                WindowManager.shared.close()
            }
        }
        .onAppear {
            
            // Local key event monitor to handle delete/pin shortcuts robustly even when search field has focus
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard !showingFolderSettings else { return event }
                let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                let expectedFlags = NSEvent.ModifierFlags(rawValue: UInt(hkDeleteModifiers)).intersection([.command, .option, .shift, .control])
                
                var isDeleteMatch = false
                if hkDeleteKey.lowercased() == "delete" {
                    isDeleteMatch = (event.keyCode == 51 || event.keyCode == 117)
                } else if let deleteChar = hkDeleteKey.lowercased().first {
                    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                    let cyrillicChar = qwertyToCyrillic[deleteChar].map { String($0) } ?? ""
                    isDeleteMatch = (chars == String(deleteChar) || (!cyrillicChar.isEmpty && chars == cyrillicChar))
                }
                
                NSLog("[SkyPaste Debug] KeyDown: keyCode=%d, chars=%@, flags=%lu, isDeleteMatch=%d, expectedFlags=%lu, hoveredItemID=%@", event.keyCode, event.charactersIgnoringModifiers ?? "", flags.rawValue, isDeleteMatch ? 1 : 0, expectedFlags.rawValue, String(describing: storage.hoveredItemID))
                
                if isDeleteMatch && flags == expectedFlags {
                    let isEditing = NSApp.keyWindow?.firstResponder is NSTextView
                    let isDeleteKey = (event.keyCode == 51 || event.keyCode == 117)
                    NSLog("[SkyPaste Debug] Match delete! isEditing=%d, isDeleteKey=%d, searchTextIsEmpty=%d", isEditing ? 1 : 0, isDeleteKey ? 1 : 0, searchText.isEmpty ? 1 : 0)
                    
                    if isDeleteKey && isEditing && !searchText.isEmpty {
                        return event // normal text deletion in search bar if search bar is not empty
                    }
                    if !isDeleteKey && isEditing && flags.isEmpty {
                        return event // let the user type the alphanumeric key into search bar
                    }
                    
                    if let id = storage.hoveredItemID {
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        NSLog("[SkyPaste Debug] Hovered item found: id=%@, selectedURLs=%@", id.uuidString, selectedURLs.map { $0.absoluteString })
                        if !selectedURLs.isEmpty {
                            withAnimation(.easeOut(duration: 0.2)) {
                                storage.deleteFiles(urlsToDelete: selectedURLs, from: id)
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                storage.deleteItem(with: id)
                            }
                        }
                        return nil // Consume keydown event
                    } else {
                        NSLog("[SkyPaste Debug] Hovered item is NIL, cannot delete!")
                    }
                }
                
                // Match pin shortcut
                let expectedPinFlags = NSEvent.ModifierFlags(rawValue: UInt(hkPinModifiers)).intersection([.command, .option, .shift, .control])
                var isPinMatch = false
                if let pinChar = hkPinKey.lowercased().first {
                    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                    let cyrillicChar = qwertyToCyrillic[pinChar].map { String($0) } ?? ""
                    isPinMatch = (chars == String(pinChar) || (!cyrillicChar.isEmpty && chars == cyrillicChar))
                }
                if isPinMatch && flags == expectedPinFlags {
                    if let id = storage.hoveredItemID {
                        let selectedURLs = storage.popoverSelectedURLs.isEmpty ? (storage.popoverHoveredURL != nil ? [storage.popoverHoveredURL!] : []) : storage.popoverSelectedURLs
                        if !selectedURLs.isEmpty, let baseItem = storage.items.first(where: { $0.id == id }) {
                            var newItem = ClipboardItem(
                                timestamp: Date(),
                                firstCopiedAt: Date(),
                                type: baseItem.type,
                                textContent: selectedURLs.map { $0.absoluteString }.joined(separator: "\n"),
                                title: selectedURLs.count > 1 ? "\(selectedURLs.count) files" : selectedURLs.first?.lastPathComponent,
                                fileURL: selectedURLs.first,
                                appSource: baseItem.appSource,
                                appBundleID: baseItem.appBundleID,
                                extensions: baseItem.extensions,
                                fileCount: selectedURLs.count
                            )
                            newItem.isPinned = true
                            withAnimation(.easeOut(duration: 0.2)) {
                                storage.addItem(newItem)
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                storage.togglePin(for: id)
                            }
                        }
                        return nil // Consume keydown event
                    }
                }
                
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SkyPasteWindowDidShow"))) { _ in
            if let panel = WindowManager.shared.panel {
                // Force AppKit to update hover states by posting a dummy mouseMoved event at window load
                let mouseLoc = panel.mouseLocationOutsideOfEventStream
                if let dummyEvent = NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: mouseLoc,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                ) {
                    panel.postEvent(dummyEvent, atStart: true)
                }
            }
        }
        .overlay {
            if let toast = storage.folderMoveToast {
                folderMoveToastView(folder: toast.folder, shortcut: toast.shortcut)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: storage.folderMoveToast != nil)
            } else if showingFolderSettings {
                FolderSettingsOverlay(
                    storage: storage,
                    folderToEdit: editingFolderInMain,
                    onDismiss: {
                        showingFolderSettings = false
                        editingFolderInMain = nil
                        itemToAssignToNewFolder = nil
                        urlsToExtractToNewFolder = nil
                        itemToExtractFrom = nil
                    },
                    onSave: { targetID in
                        if let hid = itemToAssignToNewFolder {
                            storage.assign(item: hid, to: targetID)
                        } else if let urls = urlsToExtractToNewFolder, let baseItem = itemToExtractFrom {
                            var newItem = ClipboardItem(
                                timestamp: Date(),
                                firstCopiedAt: Date(),
                                type: baseItem.type,
                                textContent: urls.map { $0.absoluteString }.joined(separator: "\n"),
                                title: urls.count > 1 ? "\(urls.count) files" : urls.first?.lastPathComponent,
                                fileURL: urls.first,
                                appSource: baseItem.appSource,
                                appBundleID: baseItem.appBundleID,
                                extensions: baseItem.extensions,
                                fileCount: urls.count
                            )
                            newItem.isPinned = false
                            newItem.folderID = targetID
                            storage.addItem(newItem)
                        }
                        showingFolderSettings = false
                        editingFolderInMain = nil
                        itemToAssignToNewFolder = nil
                        urlsToExtractToNewFolder = nil
                        itemToExtractFrom = nil
                    }
                )
            } else if showingTrashAlert {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { showingTrashAlert = false }
                    VStack(spacing: 16) {
                        Text("Clear Unpinned Items").font(.headline)
                        Text("Are you sure you want to delete all unpinned items? This action cannot be undone.")
                            .font(.caption).multilineTextAlignment(.center).foregroundColor(.secondary)
                        HStack {
                            Button("Cancel") { showingTrashAlert = false }.keyboardShortcut(.escape, modifiers: [])
                            Spacer()
                            Button("Delete & Don't Ask Again") {
                                suppressGlobalTrashWarning = true
                                storage.clearUnpinned()
                                showingTrashAlert = false
                            }
                            Button("Delete") {
                                storage.clearUnpinned()
                                showingTrashAlert = false
                            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding().frame(width: 320).background(Color(NSColor.windowBackgroundColor)).cornerRadius(12).shadow(radius: 10)
                }
            } else if showingFolderTrashAlert {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { showingFolderTrashAlert = false }
                    VStack(spacing: 16) {
                        Text("Clear Items").font(.headline)
                        Text("Do you want to clear this specific folder, or clear all unpinned items globally?")
                            .font(.caption).multilineTextAlignment(.center).foregroundColor(.secondary)
                        HStack {
                            Button("Cancel") { showingFolderTrashAlert = false }.keyboardShortcut(.escape, modifiers: [])
                            Spacer()
                            Button("Everywhere (Unpinned)") {
                                storage.clearUnpinned()
                                showingFolderTrashAlert = false
                            }
                            Button("Only In This Folder") {
                                if let fid = storage.selectedFolderID { storage.clearFolder(id: fid) }
                                showingFolderTrashAlert = false
                            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding().frame(width: 380).background(Color(NSColor.windowBackgroundColor)).cornerRadius(12).shadow(radius: 10)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search Copied History...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            Spacer()
            HStack(spacing: 8) {
                Menu {
                    Button("All Items") { storage.selectedFolderID = nil }
                    Button("Library...") {
                        let position = UserDefaults.standard.string(forKey: "popupPosition") ?? "cursor"
                        LibraryWindowManager.shared.toggle(storage: storage, position: position)
                    }
                    Button("Create New Folder...") {
                        storage.hoveredItemID = nil
                        itemToAssignToNewFolder = nil
                        urlsToExtractToNewFolder = nil
                        itemToExtractFrom = nil
                        editingFolderInMain = nil
                        showingFolderSettings = true
                    }
                    Divider()
                    ForEach(storage.folders.sorted { $0.order < $1.order }) { f in Button("\(f.displayEmoji) \(f.name)") { storage.selectedFolderID = f.id } }
                } label: { Image(systemName: storage.selectedFolderID == nil ? "folder" : "folder.fill").foregroundColor(storage.selectedFolderID == nil ? .secondary : .accentColor).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).fixedSize().help("Folders")
                
                Menu {
                    Picker("Sort By", selection: $storage.sortOption) { ForEach(SortOption.allCases, id: \.self) { opt in Text(opt.rawValue).tag(opt) } }
                } label: { Image(systemName: "arrow.up.arrow.down").foregroundColor(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).fixedSize()
                
                Button(action: {
                    if storage.selectedFolderID != nil {
                        showingFolderTrashAlert = true
                    } else {
                        if suppressGlobalTrashWarning {
                            storage.clearUnpinned()
                        } else {
                            showingTrashAlert = true
                        }
                    }
                }) { Image(systemName: "trash").foregroundColor(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Clear History")
                
                Button(action: { AppDelegate.shared.openSettings() }) { Image(systemName: "gearshape.fill").foregroundColor(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.plain).help("Preferences")
                
                Button(action: { NSApplication.shared.terminate(nil) }) { Image(systemName: "power").foregroundColor(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.plain).help("Quit SkyPaste")
            }
        }
        .padding(12)
    }
    
    private func folderHeader(_ folder: AppFolder) -> some View {
        HStack(spacing: 8) {
            Text(folder.displayEmoji).font(.title3)
            Text(folder.name).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(folder.displayColor)
            Spacer()
            Menu {
                Button("Edit folder settings...") {
                    storage.hoveredItemID = nil
                    editingFolderInMain = folder
                    showingFolderSettings = true
                }
                Divider()
                Button("Clear all items in this folder", role: .destructive) { withAnimation(.easeOut(duration: 0.2)) { storage.clearFolder(id: folder.id) } }
                Divider()
                Button("Delete folder (keep items)", role: .destructive) { withAnimation(.easeOut(duration: 0.2)) { storage.deleteFolder(id: folder.id); storage.selectedFolderID = nil } }
                Button("Delete folder and all its items", role: .destructive) { withAnimation(.easeOut(duration: 0.2)) { storage.clearFolder(id: folder.id); storage.deleteFolder(id: folder.id); storage.selectedFolderID = nil } }
                Divider()
                Button("Close") { storage.selectedFolderID = nil }
            } label: { Image(systemName: "ellipsis.circle").foregroundColor(.secondary).font(.system(size: 15)).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
    
    private var clipboardList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredItems) { item in
                    ClipboardItemRow(
                        storage: storage,
                        item: item,
                        folders: storage.folders,
                        hoveredItemID: storage.hoveredItemID,
                        selectedFolderID: storage.selectedFolderID,
                        onPin: { withAnimation(.easeOut(duration: 0.2)) { storage.togglePin(for: item.id) } },
                        onDelete: { withAnimation(.easeOut(duration: 0.2)) { storage.deleteItem(with: item.id) } },
                        onAssignToFolder: { fid in storage.assign(item: item.id, to: fid) },
                        onImageTap: { url in
                            PreviewWindowManager.shared.show(url: url)
                        },
                        onExtractFile: { urls, pin, folderID in
                            var newItem = ClipboardItem(
                                timestamp: Date(),
                                firstCopiedAt: Date(),
                                type: item.type,
                                textContent: urls.map { $0.absoluteString }.joined(separator: "\n"),
                                title: urls.count > 1 ? "\(urls.count) files" : urls.first?.lastPathComponent,
                                fileURL: urls.first,
                                appSource: item.appSource,
                                appBundleID: item.appBundleID,
                                extensions: item.extensions,
                                fileCount: urls.count
                            )
                            newItem.isPinned = pin
                            newItem.folderID = folderID
                            storage.addItem(newItem)
                        },
                        onCreateFolder: { urls in
                            if let urls = urls, !urls.isEmpty {
                                urlsToExtractToNewFolder = urls
                                itemToExtractFrom = item
                            } else {
                                itemToAssignToNewFolder = item.id
                            }
                            storage.hoveredItemID = nil
                            editingFolderInMain = nil
                            showingFolderSettings = true
                        },
                        onDeleteFiles: { urlsToDelete in
                            withAnimation(.easeOut(duration: 0.2)) {
                                storage.deleteFiles(urlsToDelete: urlsToDelete, from: item.id)
                            }
                        }
                    )
                    .id(item.id)
                    .contentShape(Rectangle())
                     .onHover { isHovered in
                         guard !showingFolderSettings else { return }
                         withAnimation(.quickSpring) {
                             if isHovered { storage.hoveredItemID = item.id }
                             else if storage.hoveredItemID == item.id { storage.hoveredItemID = nil }
                         }
                     }
                     .onTapGesture {
                         NSApp.activate(ignoringOtherApps: true)
                         let flags = (NSApp.currentEvent?.modifierFlags ?? []).union(NSEvent.modifierFlags)
                         let autoPaste = autoPasteActive
                         let defaultPlain = pastePlainActive
                         
                         if flags.contains(.command) {
                             AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: false)
                             WindowManager.shared.close()
                         } else if flags.contains(.option) && flags.contains(.shift) {
                             AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: false)
                             AppDelegate.shared.monitorRef?.triggerCmdV()
                             WindowManager.shared.close()
                         } else if flags.contains(.option) {
                             AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: true)
                             AppDelegate.shared.monitorRef?.triggerCmdV()
                             WindowManager.shared.close()
                         } else {
                             AppDelegate.shared.pasteFromClipboard(item: item, plainTextOnly: defaultPlain, shouldPaste: autoPaste)
                         }
                         
                         storage.moveToTop(for: item.id)
                     }
                     .listRowInsets(EdgeInsets())
                     .listRowBackground(Color.clear)
                     .listRowSeparator(.hidden)
                     .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    let isReorderingPinnedOnly = source.allSatisfy { filteredItems[$0].isPinned }
                    if isReorderingPinnedOnly { storage.movePinned(source: source, destination: destination) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .padding(.horizontal, 0)
            .padding(.vertical, 8)
            .onChange(of: filteredItems.first?.id) { _, topID in
                if let id = topID { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
    
    @ViewBuilder
    private func folderMoveToastView(folder: AppFolder, shortcut: String?) -> some View {
        VStack {
            HStack(spacing: 8) {
                Text(folder.displayEmoji).font(.title3)
                Text("Moved to \(folder.name)").font(.system(size: 13, weight: .semibold, design: .rounded))
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct FolderSettingsOverlay: View {
    @ObservedObject var storage: Storage
    var folderToEdit: AppFolder? // nil means create mode
    var onDismiss: () -> Void
    var onSave: (UUID) -> Void // Passes the saved/created folder ID
    
    @State private var name: String = ""
    @State private var emoji: String = "📁"
    @State private var color: Color = .accentColor
    @State private var openKey: String = ""
    @State private var openMod: Int = 0
    @State private var moveKey: String = ""
    @State private var moveMod: Int = 0
    
    @State private var showEmojiPicker = false
    @State private var appBundleIDs: [String] = []
    @State private var showingAppPicker = false
    @State private var newBundleID = ""
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture {
                onDismiss()
            }
            
            VStack(spacing: 16) {
                Text(folderToEdit == nil ? "Create Folder" : "Edit Folder")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    EmojiPickerButton(emoji: $emoji)
                        .frame(width: 36, height: 36)
                    
                    NativeColorPicker(color: $color, width: 36, height: 36)
                        .frame(width: 36, height: 36)
                    
                    TextField("Folder name...", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Open:").font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                        ShortcutRecorder(actionName: "Open \(name)", keyString: $openKey, modifiers: $openMod, onValidate: { _,_,_ in nil })
                            .frame(width: 100)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Text("Move:").font(.caption).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
                        ShortcutRecorder(actionName: "Move \(name)", keyString: $moveKey, modifiers: $moveMod, onValidate: { _,_,_ in nil })
                            .frame(width: 100)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("App Bindings", systemImage: "app.badge.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !appBundleIDs.isEmpty {
                            Text("\(appBundleIDs.count) bound")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if appBundleIDs.isEmpty {
                        Text("Not bound to any apps (global folder).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appBundleIDs, id: \.self) { bundleID in
                                    HStack(spacing: 4) {
                                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                            let icon = NSWorkspace.shared.icon(forFile: url.path)
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 12, height: 12)
                                        }
                                        Text(appName(for: bundleID))
                                            .font(.system(size: 10))
                                        Button(action: { appBundleIDs.removeAll { $0 == bundleID } }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    Button(action: { showingAppPicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Bind to Application...")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                HStack {
                    Button("Cancel") { onDismiss() }.keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    Button(folderToEdit == nil ? "Create" : "Save") {
                        let finalEmoji = emoji.isEmpty ? "📁" : emoji
                        var targetID: UUID
                        if let existing = folderToEdit {
                            var updated = existing
                            updated.emoji = finalEmoji
                            updated.colorHex = color.toHex()
                            updated.appBundleIDs = appBundleIDs
                            storage.updateFolder(updated)
                            targetID = updated.id
                        } else {
                            if name.isEmpty { name = "New Folder" }
                            storage.createFolder(name: name, emoji: finalEmoji, colorHex: color.toHex(), appBundleIDs: appBundleIDs)
                            targetID = storage.folders.last!.id
                        }
                        storage.saveFolderShortcut(folderID: targetID, type: "open", key: openKey, mod: openMod)
                        storage.saveFolderShortcut(folderID: targetID, type: "move", key: moveKey, mod: moveMod)
                        onSave(targetID)
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.isEmpty)
                }
            }
            .padding()
            .frame(width: 340)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 10)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(selectedBundleID: $newBundleID)
        }
        .onChange(of: newBundleID) { _, newValue in
            if !newValue.isEmpty, !appBundleIDs.contains(newValue) {
                appBundleIDs.append(newValue)
                newBundleID = ""
            }
        }
        .onAppear {
            if let f = folderToEdit {
                name = f.name
                emoji = f.emoji ?? "📁"
                appBundleIDs = f.appBundleIDs
                if let hex = f.colorHex, let c = Color(hex: hex) { color = c }
                if let openSc = storage.getFolderShortcut(folderID: f.id, type: "open") {
                    openKey = openSc.key; openMod = openSc.mod
                }
                if let moveSc = storage.getFolderShortcut(folderID: f.id, type: "move") {
                    moveKey = moveSc.key; moveMod = moveSc.mod
                }
            }
        }
    }
    
    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let path = url.deletingLastPathComponent().lastPathComponent
            return path.hasSuffix(".app") ? String(path.dropLast(4)) : url.lastPathComponent
        }
        return bundleID
    }
}

@MainActor
class LibraryWindowManager {
    static let shared = LibraryWindowManager()
    var panel: LibraryPanel?
    private var outsideClickMonitorLocal: Any?
    
    func toggle(storage: Storage, position: String = "cursor") {
        if let panel = panel, panel.isPresented {
            close()
            return
        }
        
        close()
        
        let foldersCount = storage.folders.count
        let estimatedLibHeight = foldersCount == 0 ? 100 : CGFloat(foldersCount * 42) + CGFloat(max(0, foldersCount - 1) * 4) + 16
        let initialHeight = min(estimatedLibHeight + 85, 440)
        
        let button = position == "statusItem" ? AppDelegate.shared.statusBarItem.button : nil
        let panel = LibraryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: initialHeight),
            contentView: NSView(),
            statusBarButton: button,
            position: position
        )
        panel.onClose = { [weak self] in
            self?.removeClickMonitors()
            self?.panel = nil
        }
        self.panel = panel
        
        let contentView = LibraryContentView(storage: storage, onClose: { [weak self] in
            self?.close()
        })
        
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView
        
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.isPresented = true
        NotificationCenter.default.post(name: NSNotification.Name("SkyPasteLibraryWindowDidShow"), object: nil)
        
        setupClickMonitors()
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    var isVisible: Bool { panel?.isPresented ?? false }
    
    func close() {
        removeClickMonitors()
        panel?.close()
        panel = nil
    }
    
    private func setupClickMonitors() {
        removeClickMonitors()
        
        // 1. Local monitor (clicks inside the app, but outside the library panel)
        outsideClickMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            let clickPoint = NSEvent.mouseLocation
            
            if !panel.frame.contains(clickPoint) {
                DispatchQueue.main.async {
                    self.close()
                }
            }
            return event
        }
        
        // 2. Observer for app resignation (clicks outside the app)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appResignedActive() {
        close()
    }
    
    private func removeClickMonitors() {
        if let monitor = outsideClickMonitorLocal {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitorLocal = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
    }
}

class LibraryPanel: FloatingPanel {
    var onClose: (() -> Void)?
    
    override func close() {
        super.close()
        onClose?()
    }
}

struct LibraryContentView: View {
    @ObservedObject var storage: Storage
    var onClose: () -> Void
    
    @State private var searchText = ""
    @State private var monitor: Any?
    @State private var currentLibraryWindowHeight: CGFloat = 440
    
    var filteredFolders: [AppFolder] {
        let sorted = storage.folders.sorted { $0.order < $1.order }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill").font(.title3).foregroundColor(.accentColor)
                Text("Library").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(filteredFolders.count)").font(.caption).foregroundColor(.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(Color.secondary.opacity(0.15)).cornerRadius(6)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search folders...", text: $searchText).textFieldStyle(.plain).font(.system(size: 13, weight: .medium, design: .rounded))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(8).background(Color.secondary.opacity(0.08)).cornerRadius(8).padding(.horizontal, 12).padding(.bottom, 6)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(filteredFolders.enumerated()), id: \.element.id) { index, folder in
                        LibraryFolderRow(folder: folder, storage: storage, onSelect: {
                            if !WindowManager.shared.isWindowVisible {
                                AppDelegate.shared.togglePopover(nil)
                            }
                            storage.selectedFolderID = folder.id
                            onClose()
                        })
                        .onDrop(of: [.text], delegate: LibraryDropDelegate(folder: folder, storage: storage))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
            }
        }
        .frame(width: 360, height: currentLibraryWindowHeight, alignment: .top)
        .glassBackground(cornerRadius: 16)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 0x35 { onClose(); return nil }
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SkyPasteLibraryWindowDidShow"))) { _ in
            if let panel = LibraryWindowManager.shared.panel {
                // Force AppKit to update hover states by posting a dummy mouseMoved event at window load
                let mouseLoc = panel.mouseLocationOutsideOfEventStream
                if let dummyEvent = NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: mouseLoc,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                ) {
                    panel.postEvent(dummyEvent, atStart: true)
                }
            }
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

struct LibraryFolderRow: View {
    let folder: AppFolder
    @ObservedObject var storage: Storage
    var onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundColor(Color(.tertiaryLabelColor)).font(.system(size: 11, weight: .medium)).frame(width: 14)
            Text(folder.displayEmoji).font(.system(size: 20)).frame(width: 30, height: 30).background(folder.displayColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.system(size: 13, weight: .semibold)).foregroundColor(folder.displayColor)
                HStack(spacing: 4) {
                    Text("\(storage.itemCount(forFolderID: folder.id))").font(.system(size: 10)).foregroundColor(.secondary)
                    if let appName = folder.appName { Text("•").font(.caption2).foregroundColor(.secondary); Text(appName).font(.system(size: 10)).foregroundColor(.secondary) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(.tertiaryLabelColor))
        }
        .onDrag { NSItemProvider(object: folder.id.uuidString as NSString) }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(Color.secondary.opacity(isHovered ? 0.12 : 0.06)).cornerRadius(8)
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

struct LibraryDropDelegate: DropDelegate {
    let folder: AppFolder
    @ObservedObject var storage: Storage
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            DispatchQueue.main.async {
                if let uuidString = obj as? String, let draggedID = UUID(uuidString: uuidString as String),
                   let fromIdx = self.storage.folders.firstIndex(where: { $0.id == draggedID }),
                   let toIdx = self.storage.folders.firstIndex(where: { $0.id == self.folder.id }),
                   fromIdx != toIdx {
                    let indices = IndexSet(integer: fromIdx)
                    self.storage.reorderFolders(from: indices, to: toIdx > fromIdx ? toIdx + 1 : toIdx)
                }
            }
        }
        return true
    }
}

// MARK: - Preference Keys

struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FolderRowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

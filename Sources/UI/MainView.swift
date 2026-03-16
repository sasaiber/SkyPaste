import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var storage: Storage
    @State private var searchText = ""
    @State private var hoveredItemID: UUID?
    
    @State private var showingCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var showClearAllConfirm = false


    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "d"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "c"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
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
        
        // Folder filter
        if let fid = storage.selectedFolderID {
            result = result.filter { $0.folderID == fid }
        }
        
        // Search filter
        if !searchText.isEmpty {
            result = result.filter { ($0.textContent ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        
        // Sorting
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
            // Folder Banner
            if let activeFolder = storage.folders.first(where: { $0.id == storage.selectedFolderID }) {
                HStack(spacing: 8) {
                    Text(activeFolder.displayEmoji)
                        .font(.title3)
                    Text(activeFolder.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(activeFolder.displayColor)
                    
                    Spacer()
                    
                    // Folder actions — one button, clear labels
                    Menu {
                        Button("Clear all items in this folder", role: .destructive) {
                            storage.clearFolder(id: activeFolder.id)
                        }
                        Divider()
                        Button("Delete folder (keep items)", role: .destructive) {
                            storage.deleteFolder(id: activeFolder.id)
                            storage.selectedFolderID = nil
                        }
                        Button("Delete folder and all its items", role: .destructive) {
                            storage.clearFolder(id: activeFolder.id)
                            storage.deleteFolder(id: activeFolder.id)
                            storage.selectedFolderID = nil
                        }
                        Divider()
                        Button("Close") { storage.selectedFolderID = nil }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(activeFolder.displayColor.opacity(0.1))
                Divider()
            }
            
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Copied History...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer()
                
                // Folders Menu
                Menu {
                    Button("All Items") { storage.selectedFolderID = nil }
                    Divider()
                    ForEach(storage.folders) { f in
                        Button("\(f.displayEmoji) \(f.name)") { storage.selectedFolderID = f.id }
                    }
                } label: {
                    Image(systemName: storage.selectedFolderID == nil ? "folder" : "folder.fill")
                        .foregroundColor(storage.selectedFolderID == nil ? .secondary : .accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Sort Menu
                Menu {
                    Picker("Sort By", selection: $storage.sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Menu {
                    Button("Clear all unpinned items", role: .destructive) {
                        storage.clearUnpinned()
                    }
                    Button("Clear all text history", role: .destructive) {
                        storage.clearUnpinnedText(folderID: storage.selectedFolderID)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Clear History")
                .padding(.horizontal, 4)
                
                Button(action: {
                    AppDelegate.shared.openSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preferences")
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit SkyPaste")
            }
            .padding(12)
            .background(Material.ultraThin)
            
            // Global quit shortcuts for accessory mode
            Group {
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("q", modifiers: .command)
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("й", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            
            // Hidden buttons for keyboard shortcuts
            let qwertyToCyrillic: [Character: Character] = [
                "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
                "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
                "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю", "/": "."
            ]
            
            Group {
                if let pinChar = hkPinKey.lowercased().first {
                    Button(action: {
                        if let id = hoveredItemID { storage.togglePin(for: id) }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(pinChar), modifiers: eventModifiers(from: hkPinModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[pinChar] {
                        Button(action: {
                            if let id = hoveredItemID { storage.togglePin(for: id) }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkPinModifiers))
                    }
                }
                
                if let deleteChar = hkDeleteKey.lowercased().first {
                    Button(action: {
                        if let id = hoveredItemID { storage.deleteItem(with: id) }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(deleteChar), modifiers: eventModifiers(from: hkDeleteModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[deleteChar] {
                        Button(action: {
                            if let id = hoveredItemID { storage.deleteItem(with: id) }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkDeleteModifiers))
                    }
                }
                
                if let folderChar = hkFolderKey.lowercased().first {
                    Button(action: {
                        if hoveredItemID != nil {
                            newFolderName = ""
                            showingCreateFolderAlert = true
                        }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(folderChar), modifiers: eventModifiers(from: hkFolderModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[folderChar] {
                        Button(action: {
                            if hoveredItemID != nil {
                                newFolderName = ""
                                showingCreateFolderAlert = true
                            }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkFolderModifiers))
                    }
                }
                
                // Explicit Quit handler for CMD+Q
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            
            Divider()
            
            // List
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredItems) { item in
                        ClipboardItemRow(
                            item: item,
                            folders: storage.folders,
                            hoveredItemID: hoveredItemID,
                            selectedFolderID: storage.selectedFolderID,
                            onPin: { storage.togglePin(for: item.id) },
                            onDelete: { storage.deleteItem(with: item.id) },
                            onAssignToFolder: { fid in storage.assign(item: item.id, to: fid) }
                        )
                            .id(item.id)
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredItemID = item.id
                                } else if hoveredItemID == item.id {
                                    hoveredItemID = nil
                                }
                            }
                            .onTapGesture {
                                let flags = NSApp.currentEvent?.modifierFlags ?? []
                                let autoPaste = UserDefaults.standard.bool(forKey: "autoPasteActive")
                                let defaultPlain = UserDefaults.standard.bool(forKey: "pastePlainActive")
                                
                                if flags.contains(.command) {
                                    AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: false)
                                } else if flags.contains(.option) && flags.contains(.shift) {
                                    AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: false)
                                    AppDelegate.shared.monitorRef?.triggerCmdV()
                                } else if flags.contains(.option) {
                                    AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: true)
                                    AppDelegate.shared.monitorRef?.triggerCmdV()
                                } else {
                                    AppDelegate.shared.monitorRef?.copyToPasteboard(item: item, plainTextOnly: defaultPlain)
                                    if autoPaste {
                                        AppDelegate.shared.monitorRef?.triggerCmdV()
                                    }
                                }
                                
                                storage.moveToTop(for: item.id)
                                AppDelegate.shared.popover.performClose(nil)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        let isReorderingPinnedOnly = source.allSatisfy { filteredItems[$0].isPinned }
                        if isReorderingPinnedOnly {
                            storage.movePinned(source: source, destination: destination)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: filteredItems.first?.id) { _, topID in
                    if let id = topID {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
            
        }
        .frame(width: 400, height: 600)
        // macOS Tahoe style background window
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onExitCommand {
            AppDelegate.shared.popover.performClose(nil)
        }
        .alert("Create Folder", isPresented: $showingCreateFolderAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create", action: {
                if !newFolderName.isEmpty {
                    storage.createFolder(name: newFolderName)
                    if let f = storage.folders.last, let hid = hoveredItemID {
                        storage.assign(item: hid, to: f.id)
                    }
                }
            })
        } message: {
            Text("Enter a name. The hovered item will be assigned to it automatically.")
        }
    }
}

// Helper to use NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

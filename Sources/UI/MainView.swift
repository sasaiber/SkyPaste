import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var storage: Storage
    @State private var searchText = ""
    @State private var itemToAssignToNewFolder: UUID?
    
    @State private var showingFolderSettings = false
    @State private var editingFolderInMain: AppFolder? = nil
    
    @State private var showingTrashAlert = false
    @State private var showingFolderTrashAlert = false
    @AppStorage("suppressGlobalTrashWarning") private var suppressGlobalTrashWarning: Bool = false

    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "f"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
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
            
            let qwertyToCyrillic: [Character: Character] = [
                "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
                "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д",
                "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю",
            ]
            
            Group {
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }.keyboardShortcut("q", modifiers: .command)
                Button(action: { NSApplication.shared.terminate(nil) }) { EmptyView() }.keyboardShortcut("й", modifiers: .command)
                
                if let pinChar = hkPinKey.lowercased().first {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        withAnimation(.smoothSpring) { storage.togglePin(for: id) }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(pinChar), modifiers: eventModifiers(from: hkPinModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[pinChar] {
                        Button(action: {
                            guard let id = storage.hoveredItemID else { return }
                            withAnimation(.smoothSpring) { storage.togglePin(for: id) }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkPinModifiers))
                    }
                }
                
                if hkDeleteKey.lowercased() == "delete" {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        withAnimation(.smoothSpring) { storage.deleteItem(with: id) }
                    }) { EmptyView() }
                        .keyboardShortcut(.delete, modifiers: eventModifiers(from: hkDeleteModifiers))
                } else if let deleteChar = hkDeleteKey.lowercased().first {
                    Button(action: {
                        guard let id = storage.hoveredItemID else { return }
                        withAnimation(.smoothSpring) { storage.deleteItem(with: id) }
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(deleteChar), modifiers: eventModifiers(from: hkDeleteModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[deleteChar] {
                        Button(action: {
                            guard let id = storage.hoveredItemID else { return }
                            withAnimation(.smoothSpring) { storage.deleteItem(with: id) }
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkDeleteModifiers))
                    }
                }
                
                if let folderChar = hkFolderKey.lowercased().first {
                    Button(action: {
                        storage.hoveredItemID = nil
                        itemToAssignToNewFolder = storage.hoveredItemID
                        editingFolderInMain = nil
                        showingFolderSettings = true
                    }) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(folderChar), modifiers: eventModifiers(from: hkFolderModifiers))
                    
                    if let cyrillic = qwertyToCyrillic[folderChar] {
                        Button(action: {
                            storage.hoveredItemID = nil
                            itemToAssignToNewFolder = storage.hoveredItemID
                            editingFolderInMain = nil
                            showingFolderSettings = true
                        }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent(cyrillic), modifiers: eventModifiers(from: hkFolderModifiers))
                    }
                }
            }
            .frame(width: 0, height: 0).opacity(0)
            
            Divider()
            
            clipboardList
        }
        .frame(width: 400, height: 600)
        .glassBackground(cornerRadius: 16)
        .edgesIgnoringSafeArea(.all)
        .onExitCommand { WindowManager.shared.close() }
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
                    },
                    onSave: { targetID in
                        if let hid = itemToAssignToNewFolder { storage.assign(item: hid, to: targetID) }
                        showingFolderSettings = false
                        editingFolderInMain = nil
                        itemToAssignToNewFolder = nil
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
                    Divider()
                    ForEach(storage.folders) { f in Button("\(f.displayEmoji) \(f.name)") { storage.selectedFolderID = f.id } }
                } label: { Image(systemName: storage.selectedFolderID == nil ? "folder" : "folder.fill").foregroundColor(storage.selectedFolderID == nil ? .secondary : .accentColor).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).fixedSize()
                
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
                Button("Clear all items in this folder", role: .destructive) { storage.clearFolder(id: folder.id) }
                Divider()
                Button("Delete folder (keep items)", role: .destructive) { storage.deleteFolder(id: folder.id); storage.selectedFolderID = nil }
                Button("Delete folder and all its items", role: .destructive) { storage.clearFolder(id: folder.id); storage.deleteFolder(id: folder.id); storage.selectedFolderID = nil }
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
                        item: item,
                        folders: storage.folders,
                        hoveredItemID: storage.hoveredItemID,
                        selectedFolderID: storage.selectedFolderID,
                        onPin: { withAnimation(.smoothSpring) { storage.togglePin(for: item.id) } },
                        onDelete: { withAnimation(.smoothSpring) { storage.deleteItem(with: item.id) } },
                        onAssignToFolder: { fid in storage.assign(item: item.id, to: fid) }
                    )
                    .id(item.id)
                     .onHover { isHovered in
                         guard !showingFolderSettings else { return }
                         withAnimation(.quickSpring) {
                             if isHovered { storage.hoveredItemID = item.id }
                             else if storage.hoveredItemID == item.id { storage.hoveredItemID = nil }
                         }
                     }
                     .onTapGesture {
                         NSApp.activate(ignoringOtherApps: true)
                         let flags = NSApp.currentEvent?.modifierFlags ?? []
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
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture {
                if !AppDelegate.shared.isPickingEmoji {
                    onDismiss()
                }
            }
            
            VStack(spacing: 16) {
                Text(folderToEdit == nil ? "Create Folder" : "Edit Folder")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    EmojiPickerButton(emoji: $emoji)
                        .frame(width: 36, height: 36)
                    
                    ColorPicker("", selection: $color).labelsHidden().frame(width: 30)
                    
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
                            storage.updateFolder(updated)
                            targetID = updated.id
                        } else {
                            if name.isEmpty { name = "New Folder" }
                            storage.createFolder(name: name, emoji: finalEmoji, colorHex: color.toHex())
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
            .frame(width: 320)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 10)
        }
        .onAppear {
            if let f = folderToEdit {
                name = f.name
                emoji = f.emoji ?? "📁"
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
}

import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var storage: Storage
    
    @AppStorage("cacheLimitMB") private var limitMB: Double = 999.0
    @AppStorage("retainDays") private var retainDays: Int = 30
    @AppStorage("neverDelete") private var neverDelete: Bool = false
    @AppStorage("popupPosition") private var popupPosition: String = "cursor"
    @AppStorage("autoPasteActive") private var autoPasteActive: Bool = true
    @AppStorage("pastePlainActive") private var pastePlainActive: Bool = false
    @AppStorage("previewDelay") private var previewDelay: Double = 200
    @AppStorage("showSpecialSymbols") private var showSpecialSymbols: Bool = true
    
    @State private var launchAtLogin: Bool = false
    
    @AppStorage("saveText") private var saveText: Bool = true
    @AppStorage("saveImages") private var saveImages: Bool = true
    @AppStorage("saveLinks") private var saveLinks: Bool = true
    @AppStorage("saveFiles") private var saveFiles: Bool = true
    
    @State private var folderShortcuts: [UUID: (key: String, mod: Int)] = [:]

    @AppStorage("hk1Key") private var hk1Key: String = "v"
    @AppStorage("hk1Modifiers") private var hk1Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    @AppStorage("hk2Key") private var hk2Key: String = "v"
    @AppStorage("hk2Modifiers") private var hk2Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue)

    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "d"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "c"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Shortcuts").tag(1)
                Text("Storage").tag(2)
                Text("Folders").tag(3)
                Text("About").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            
            ScrollView {
                Form {
                    switch selectedTab {
                    case 0:
                        Section("Startup") {
                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    setLaunchAtLogin(newValue)
                                }
                        }
                        
                        Section("Behavior") {
                            Toggle("Automatically paste selected item", isOn: $autoPasteActive)
                            Toggle("Paste without formatting by default", isOn: $pastePlainActive)
                        }
                        
                        Section("Appearance") {
                            Picker("Popup Position:", selection: $popupPosition) {
                                Text("Mouse Cursor").tag("cursor")
                                Text("Menu Bar Icon").tag("statusItem")
                                Text("Screen Center").tag("center")
                            }
                            
                            LabeledContent("Preview Delay:") {
                                HStack(spacing: 8) {
                                    Slider(value: $previewDelay, in: 0...2000, step: 50)
                                    Text("\(Int(previewDelay)) ms")
                                        .frame(width: 60, alignment: .leading)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Toggle("Show special symbols (⏎ ⇥ etc.)", isOn: $showSpecialSymbols)
                        }
                        
                        Section("Content Types") {
                            Toggle("Text & Rich Text", isOn: $saveText)
                            Toggle("Images & Screenshots", isOn: $saveImages)
                            Toggle("Web Links", isOn: $saveLinks)
                            Toggle("Files & Folders", isOn: $saveFiles)
                        }
                        
                        Section {
                            Button("Grant Accessibility Permissions") {
                                AppDelegate.shared.showWelcomeWindow()
                            }
                            Text("Only required for Auto-paste (⌘V simulation).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case 1:
                        Section("Global Shortcuts") {
                            LabeledContent("Show SkyPaste:") {
                                ShortcutRecorder(actionName: "Show SkyPaste", keyString: $hk1Key, modifiers: $hk1Modifiers, onValidate: checkForDuplicate)
                            }
                            LabeledContent("Paste Plain Text:") {
                                ShortcutRecorder(actionName: "Paste Plain Text", keyString: $hk2Key, modifiers: $hk2Modifiers, onValidate: checkForDuplicate)
                            }
                        }
                        
                        Section("In-App Shortcuts") {
                            LabeledContent("Quick Pin:") {
                                ShortcutRecorder(actionName: "Quick Pin", keyString: $hkPinKey, modifiers: $hkPinModifiers, onValidate: checkForDuplicate)
                            }
                            LabeledContent("Quick Delete:") {
                                ShortcutRecorder(actionName: "Quick Delete", keyString: $hkDeleteKey, modifiers: $hkDeleteModifiers, onValidate: checkForDuplicate)
                            }
                            LabeledContent("Create Folder:") {
                                ShortcutRecorder(actionName: "Create Folder", keyString: $hkFolderKey, modifiers: $hkFolderModifiers, onValidate: checkForDuplicate)
                            }
                            Text("Click any button to record a new combination.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case 2:
                        Section("Storage") {
                            LabeledContent("Maximum Size:") {
                                HStack(spacing: 8) {
                                    Slider(value: $limitMB, in: 10...9999, step: 10)
                                    TextField("", value: $limitMB, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 55)
                                    Text("MB")
                                        .foregroundColor(.secondary)
                                        .fixedSize()
                                }
                            }
                            
                            Toggle("Never delete automatically", isOn: $neverDelete)
                            
                            if !neverDelete {
                                LabeledContent("Retain items for:") {
                                    HStack(spacing: 8) {
                                        Slider(value: Binding(get: { Double(retainDays) }, set: { retainDays = Int($0) }), in: 1...365, step: 1)
                                        TextField("", value: $retainDays, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 55)
                                        Text("Days")
                                            .foregroundColor(.secondary)
                                            .fixedSize()
                                    }
                                }
                            }
                            
                            Button(role: .destructive, action: {
                                storage.clearUnpinned()
                            }) {
                                Text("Clear All Unpinned History")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        
                    case 3:
                        FoldersTabView(
                            storage: storage,
                            folderShortcuts: $folderShortcuts,
                            editingFolder: $editingFolder,
                            folderToDelete: $folderToDelete,
                            showDeleteConfirmation: $showDeleteConfirmation,
                            onValidate: checkForDuplicate,
                            onSaveShortcuts: saveFolderShortcuts
                        )
                        
                    case 4:
                        AboutTabView()
                    default:
                        EmptyView()
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loadFolderShortcuts()
        }
        .alert("Delete Folder", isPresented: $showDeleteConfirmation, presenting: folderToDelete) { folder in
            Button("Delete Folder & Items", role: .destructive) {
                storage.clearFolder(id: folder.id)
                storage.deleteFolder(id: folder.id)
            }
            Button("Keep Items, Delete Folder", role: .none) {
                storage.deleteFolder(id: folder.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Folder \"\(folder.name)\" contains \(storage.items.filter { $0.folderID == folder.id }.count) items. What would you like to do?")
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditView(folder: folder, storage: storage)
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently handle — user can re-toggle
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    // MARK: - Folder State
    @State private var newFolderName = ""
    @State private var newFolderEmoji = "📁"
    @State private var newFolderColor = Color.accentColor
    @State private var editingFolder: AppFolder? = nil
    @State private var folderToDelete: AppFolder? = nil
    @State private var showDeleteConfirmation = false
    
    private func loadFolderShortcuts() {
        if let data = UserDefaults.standard.data(forKey: "folderShortcuts"),
           let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
            var temp: [UUID: (key: String, mod: Int)] = [:]
            for sc in decoded {
                temp[sc.folderID] = (sc.keyText, sc.modifiers)
            }
            folderShortcuts = temp
        }
    }
    
    private func saveFolderShortcuts() {
        let array = folderShortcuts.map { HotkeyManager.FolderShortcut(folderID: $0.key, keyText: $0.value.key, modifiers: $0.value.mod) }
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: "folderShortcuts")
        }
        // Force hotkey manager to reload bounds
        HotkeyManager.shared.start()
    }
    
    private func checkForDuplicate(key: String, modifiers: Int, actionName: String) -> String? {
        var allShortcuts: [(name: String, key: String, mod: Int)] = [
            ("Show SkyPaste", hk1Key, hk1Modifiers),
            ("Paste Plain Text", hk2Key, hk2Modifiers),
            ("Quick Pin", hkPinKey, hkPinModifiers),
            ("Quick Delete", hkDeleteKey, hkDeleteModifiers),
            ("Create Folder", hkFolderKey, hkFolderModifiers)
        ]
        
        for (id, sc) in folderShortcuts {
            if let folder = storage.folders.first(where: { $0.id == id }) {
                allShortcuts.append(("Folder '\(folder.name)'", sc.key, sc.mod))
            }
        }
        
        for sc in allShortcuts {
            if sc.name != actionName && sc.key.lowercased() == key.lowercased() && sc.mod == modifiers {
                return "In use by \(sc.name)"
            }
        }
        return nil
    }
}

struct ShortcutRecorder: View {
    var actionName: String = ""
    @Binding var keyString: String
    @Binding var modifiers: Int
    var onValidate: ((String, Int, String) -> String?)? = nil
    
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                isRecording.toggle()
                if isRecording { 
                    self.errorMessage = nil
                    startRecording() 
                } else { stopRecording() }
            }) {
                Text(isRecording ? "Listening..." : formatShortcut())
                    .frame(width: 100)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : (errorMessage != nil ? .red : .secondary))
            .onDisappear { stopRecording() }
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func formatShortcut() -> String {
        guard !keyString.isEmpty else { return "None" }
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyString.uppercased()
        return result
    }
    
    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let char = event.charactersIgnoringModifiers, !char.isEmpty {
                if let err = onValidate?(char, Int(flags.rawValue), actionName) {
                    self.errorMessage = err
                    self.isRecording = false
                    self.stopRecording()
                    return nil
                }
                
                self.keyString = char
                self.modifiers = Int(flags.rawValue)
                self.isRecording = false
                self.stopRecording()
                return nil // Consume event
            }
            return event
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

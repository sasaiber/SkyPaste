import SwiftUI
import ServiceManagement
import ApplicationServices
import UserNotifications

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
    @AppStorage("enableNotifications") private var enableNotifications: Bool = true
    @AppStorage("launchAtLoginEnabled") private var launchAtLogin: Bool = false
    
    @AppStorage("saveText") private var saveText: Bool = true
    @AppStorage("saveImages") private var saveImages: Bool = true
    @AppStorage("saveLinks") private var saveLinks: Bool = true
    @AppStorage("saveFiles") private var saveFiles: Bool = true
    
    @State private var folderShortcuts: [UUID: (key: String, mod: Int)] = [:]
    @State private var folderMoveShortcuts: [UUID: (key: String, mod: Int)] = [:]

    @AppStorage("hk1Key") private var hk1Key: String = "s"
    @AppStorage("hk1Modifiers") private var hk1Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hk2Key") private var hk2Key: String = "v"
    @AppStorage("hk2Modifiers") private var hk2Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue)

    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "f"
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
                                    UserDefaults.standard.set(newValue, forKey: "launchAtLoginEnabled")
                                    if #available(macOS 13.0, *) {
                                        if newValue {
                                            try? SMAppService.mainApp.register()
                                        } else {
                                            try? SMAppService.mainApp.unregister()
                                        }
                                    } else {
                                        SMLoginItemSetEnabled("com.sky.skypaste" as CFString, newValue)
                                    }
                                }
                        }
                        
                        Section("Behavior") {
                            Toggle("Automatically paste selected item", isOn: $autoPasteActive)
                                .onChange(of: autoPasteActive) { _, newValue in
                                    if newValue && !AXIsProcessTrusted() {
                                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                                        _ = AXIsProcessTrustedWithOptions(opts)
                                    }
                                }
                            Toggle("Paste without formatting by default", isOn: $pastePlainActive)
                            Toggle("Show notifications for copy/paste", isOn: $enableNotifications)
                                .onChange(of: enableNotifications) { _, newValue in
                                    if newValue {
                                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                                            DispatchQueue.main.async {
                                                switch settings.authorizationStatus {
                                                case .notDetermined:
                                                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                                                case .denied, .provisional:
                                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                                        NSWorkspace.shared.open(url)
                                                    }
                                                case .authorized:
                                                    break
                                                @unknown default:
                                                    break
                                                }
                                            }
                                        }
                                    }
                                }
                        }
                        
                        Section("Appearance") {
                            Picker("Popup Position:", selection: $popupPosition) {
                                Text("Mouse Cursor").tag("cursor")
                                Text("Menu Bar Icon").tag("statusItem")
                                Text("Screen Center").tag("center")
                            }
                            
                             LabeledContent("Preview Delay:") {
                                 HStack(spacing: 12) {
                                     Slider(value: $previewDelay, in: 0...2000, step: 50)
                                         .tint(.accentColor)
                                         .frame(minWidth: 180)
                                     Text("\(Int(previewDelay)) ms")
                                         .frame(width: 65, alignment: .trailing)
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
                        StorageTabView(storage: storage)
                        
                    case 3:
                        FoldersTabView(
                            storage: storage,
                            folderShortcuts: $folderShortcuts,
                            folderMoveShortcuts: $folderMoveShortcuts,
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
            if #available(macOS 13.0, *) {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            loadFolderShortcuts()
            if enableNotifications {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
        .onChange(of: hk1Key) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hk1Modifiers) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hk2Key) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hk2Modifiers) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkPinKey) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkPinModifiers) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkDeleteKey) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkDeleteModifiers) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkFolderKey) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
        }
        .onChange(of: hkFolderModifiers) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HotkeyManager.shared.start()
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
            Text("Folder \"\(folder.name)\" contains \(storage.itemCount(forFolderID: folder.id)) items. What would you like to do?")
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditView(folder: folder, storage: storage)
        }
    }
    

    
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
        if let data = UserDefaults.standard.data(forKey: "folderMoveShortcuts"),
           let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
            var temp: [UUID: (key: String, mod: Int)] = [:]
            for sc in decoded {
                temp[sc.folderID] = (sc.keyText, sc.modifiers)
            }
            folderMoveShortcuts = temp
        }
    }
    
    private func saveFolderShortcuts() {
        let array = folderShortcuts.map { HotkeyManager.FolderShortcut(folderID: $0.key, keyText: $0.value.key, modifiers: $0.value.mod) }
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: "folderShortcuts")
        }
        let moveArray = folderMoveShortcuts.map { HotkeyManager.FolderShortcut(folderID: $0.key, keyText: $0.value.key, modifiers: $0.value.mod) }
        if let data = try? JSONEncoder().encode(moveArray) {
            UserDefaults.standard.set(data, forKey: "folderMoveShortcuts")
        }
        HotkeyManager.shared.start()
    }
    
    private func checkForDuplicate(key: String, modifiers: Int, actionName: String) -> String? {
        let targetKey = key.lowercased()
        
        let globalShortcuts: [(name: String, key: String, mod: Int)] = [
            ("Show SkyPaste", hk1Key, hk1Modifiers),
            ("Paste Plain Text", hk2Key, hk2Modifiers),
            ("Quick Pin", hkPinKey, hkPinModifiers),
            ("Quick Delete", hkDeleteKey, hkDeleteModifiers),
            ("Create Folder", hkFolderKey, hkFolderModifiers)
        ]
        
        for sc in globalShortcuts {
            if sc.name != actionName && sc.key.lowercased() == targetKey && sc.mod == modifiers {
                return "In use by \(sc.name)"
            }
        }
        
        for (id, sc) in folderShortcuts {
            if sc.key.lowercased() == targetKey && sc.mod == modifiers {
                if let folder = storage.folders.first(where: { $0.id == id }) {
                    let folderName = "Open '\(folder.name)'"
                    if folderName != actionName {
                        return "In use by \(folderName)"
                    }
                }
            }
        }
        
        for (id, sc) in folderMoveShortcuts {
            if sc.key.lowercased() == targetKey && sc.mod == modifiers {
                if let folder = storage.folders.first(where: { $0.id == id }) {
                    let folderName = "Move to '\(folder.name)'"
                    if folderName != actionName {
                        return "In use by \(folderName)"
                    }
                }
            }
        }
        
        return nil
    }
}

import SwiftUI
import ServiceManagement
import ApplicationServices
import UserNotifications

struct PreferencesView: View {
    @ObservedObject var storage: Storage
    
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
                if selectedTab == 3 {
                    FoldersTabWrapper(storage: storage)
                        .padding(16)
                } else if selectedTab == 4 {
                    AboutTabView()
                } else {
                    Form {
                        switch selectedTab {
                        case 0: GeneralTabView()
                        case 1: ShortcutsTabView()
                        case 2: StorageTabView(storage: storage)
                        default: EmptyView()
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .frame(width: 500, height: 450)
    }
}

struct GeneralTabView: View {
    @AppStorage("launchAtLoginEnabled") private var launchAtLogin: Bool = false
    @AppStorage("autoPasteActive") private var autoPasteActive: Bool = true
    @AppStorage("pastePlainActive") private var pastePlainActive: Bool = false
    @AppStorage("enableNotifications") private var enableNotifications: Bool = true
    @AppStorage("timeFormat") private var timeFormat: String = "24h"
    @AppStorage("popupPosition") private var popupPosition: String = "cursor"
    @AppStorage("previewDelay") private var previewDelay: Double = 200
    @AppStorage("showSpecialSymbols") private var showSpecialSymbols: Bool = true
    @AppStorage("disableMediaPreviews") private var disableMediaPreviews: Bool = false
    @AppStorage("unlimitedMediaPreviews") private var unlimitedMediaPreviews: Bool = true
    @AppStorage("maxPreviewsLimit") private var maxPreviewsLimit: Int = 10
    @AppStorage("saveText") private var saveText: Bool = true
    @AppStorage("saveImages") private var saveImages: Bool = true
    @AppStorage("saveLinks") private var saveLinks: Bool = true
    @AppStorage("saveFiles") private var saveFiles: Bool = true
    
    var body: some View {
        Section("Startup") {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "launchAtLoginEnabled")
                    if #available(macOS 13.0, *) {
                        if newValue {
                            SMAppService.mainApp.registerSafe()
                        } else {
                            SMAppService.mainApp.unregisterSafe()
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
            Picker("Time format", selection: $timeFormat) {
                Text("24-hour").tag("24h")
                Text("AM/PM").tag("ampm")
            }
            .pickerStyle(.segmented)
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
                                case .authorized: break
                                @unknown default: break
                                }
                            }
                        }
                    }
                }
            
            Toggle("Show media preview thumbnails", isOn: Binding(
                get: { !disableMediaPreviews },
                set: { disableMediaPreviews = !$0 }
            ))
            if !disableMediaPreviews {
                Toggle("Unlimited previews", isOn: $unlimitedMediaPreviews)
                if !unlimitedMediaPreviews {
                    HStack {
                        Text("Max preview count:")
                        Spacer()
                        TextField("", value: $maxPreviewsLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
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
                    Slider(value: $previewDelay, in: 0...2000, step: 50).tint(.accentColor).frame(minWidth: 180)
                    Text("\(Int(previewDelay)) ms").frame(width: 65, alignment: .trailing).monospacedDigit().foregroundColor(.secondary)
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
            Button("Grant Accessibility Permissions") { AppDelegate.shared.showWelcomeWindow() }
            Text("Only required for Auto-paste (⌘V simulation).").font(.caption).foregroundColor(.secondary)
        }
    }
}

struct ShortcutsTabView: View {
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
    @AppStorage("hkFinderKey") private var hkFinderKey: String = "f"
    @AppStorage("hkFinderModifiers") private var hkFinderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    @AppStorage("hkLibraryKey") private var hkLibraryKey: String = "a"
    @AppStorage("hkLibraryModifiers") private var hkLibraryModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue)
    
    var body: some View {
        Section("Global Shortcuts") {
            LabeledContent("Show SkyPaste:") {
                ShortcutRecorder(actionName: "Show SkyPaste", keyString: $hk1Key, modifiers: $hk1Modifiers)
            }
            LabeledContent("Paste Plain Text:") {
                ShortcutRecorder(actionName: "Paste Plain Text", keyString: $hk2Key, modifiers: $hk2Modifiers)
            }
        }
        Section("In-App Shortcuts") {
            LabeledContent("Quick Pin:") {
                ShortcutRecorder(actionName: "Quick Pin", keyString: $hkPinKey, modifiers: $hkPinModifiers)
            }
            LabeledContent("Quick Delete:") {
                ShortcutRecorder(actionName: "Quick Delete", keyString: $hkDeleteKey, modifiers: $hkDeleteModifiers)
            }
            LabeledContent("Create Folder:") {
                ShortcutRecorder(actionName: "Create Folder", keyString: $hkFolderKey, modifiers: $hkFolderModifiers)
            }
            LabeledContent("View in Finder:") {
                ShortcutRecorder(actionName: "View in Finder", keyString: $hkFinderKey, modifiers: $hkFinderModifiers)
            }
            LabeledContent("Library (Folders):") {
                ShortcutRecorder(actionName: "Library", keyString: $hkLibraryKey, modifiers: $hkLibraryModifiers)
            }
            Text("Click any button to record a new combination.").font(.caption).foregroundColor(.secondary)
        }
    }
}

struct FoldersTabWrapper: View {
    @ObservedObject var storage: Storage
    @State private var folderShortcuts: [UUID: (key: String, mod: Int)] = [:]
    @State private var folderMoveShortcuts: [UUID: (key: String, mod: Int)] = [:]
    @State private var editingFolder: AppFolder? = nil
    @State private var folderToDelete: AppFolder? = nil
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        FoldersTabView(
            storage: storage,
            folderShortcuts: $folderShortcuts,
            folderMoveShortcuts: $folderMoveShortcuts,
            editingFolder: $editingFolder,
            folderToDelete: $folderToDelete,
            showDeleteConfirmation: $showDeleteConfirmation,
            onValidate: nil,
            onSaveShortcuts: {
                let array = folderShortcuts.map { HotkeyManager.FolderShortcut(folderID: $0.key, keyText: $0.value.key, modifiers: $0.value.mod) }
                if let data = try? JSONEncoder().encode(array) { UserDefaults.standard.set(data, forKey: "folderShortcuts") }
                let moveArray = folderMoveShortcuts.map { HotkeyManager.FolderShortcut(folderID: $0.key, keyText: $0.value.key, modifiers: $0.value.mod) }
                if let data = try? JSONEncoder().encode(moveArray) { UserDefaults.standard.set(data, forKey: "folderMoveShortcuts") }
                HotkeyManager.shared.start()
            }
        )
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "folderShortcuts"),
               let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
                var temp: [UUID: (key: String, mod: Int)] = [:]
                for sc in decoded { temp[sc.folderID] = (sc.keyText, sc.modifiers) }
                folderShortcuts = temp
            }
            if let data = UserDefaults.standard.data(forKey: "folderMoveShortcuts"),
               let decoded = try? JSONDecoder().decode([HotkeyManager.FolderShortcut].self, from: data) {
                var temp: [UUID: (key: String, mod: Int)] = [:]
                for sc in decoded { temp[sc.folderID] = (sc.keyText, sc.modifiers) }
                folderMoveShortcuts = temp
            }
        }
        .alert("Delete Folder", isPresented: $showDeleteConfirmation, presenting: folderToDelete) { folder in
            Button("Delete Folder & Items", role: .destructive) { storage.clearFolder(id: folder.id); storage.deleteFolder(id: folder.id) }
            Button("Keep Items, Delete Folder", role: .none) { storage.deleteFolder(id: folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Folder \"\(folder.name)\" contains \(storage.itemCount(forFolderID: folder.id)) items. What would you like to do?")
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditView(folder: folder, storage: storage)
        }
    }
}

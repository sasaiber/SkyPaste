import SwiftUI

struct FolderEditView: View {
    var folder: AppFolder
    @ObservedObject var storage: Storage
    @Environment(\.dismiss) var dismiss
    
    @State private var editedName: String
    @State private var editedEmoji: String
    @State private var editedColor: Color
    @State private var appBundleIDs: [String]
    @State private var editedStackPinned: Bool
    @State private var editedStackThreshold: Int
    
    @State private var newBundleID = ""
    @State private var showingAppPicker = false

    @State private var nameError: String?
    @State private var bindingConflictError: String?

    private var hasErrors: Bool { nameError != nil }
    
    init(folder: AppFolder, storage: Storage) {
        self.folder = folder
        self.storage = storage
        _editedName = State(initialValue: folder.name)
        _editedEmoji = State(initialValue: folder.emoji ?? "📁")
        if let hex = folder.colorHex, let c = Color(hex: hex) {
            _editedColor = State(initialValue: c)
        } else {
            _editedColor = State(initialValue: .accentColor)
        }
        _appBundleIDs = State(initialValue: folder.appBundleIDs)
        _editedStackPinned = State(initialValue: folder.stackPinned)
        _editedStackThreshold = State(initialValue: folder.stackThreshold)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(folder.appBundleIDs.isEmpty ? "Edit Folder" : "Edit Folder")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 20) {
                    identitySection
                    VStack(spacing: 8) {
                        Toggle(isOn: $editedStackPinned) {
                            HStack {
                                Image(systemName: "square.on.square")
                                    .foregroundColor(.accentColor)
                                Text("Stack pinned items")
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        
                        if editedStackPinned {
                            HStack {
                                Text("Min items:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                TextField("", value: $editedStackThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                                    .controlSize(.small)
                                Stepper(value: $editedStackThreshold, in: 2...99) {
                                    EmptyView()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(12)
                    
                    appBindingsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if storage.folderNameExists(editedName, excluding: folder.id) {
                        nameError = "A folder with this name already exists."
                        return
                    }
                    var updated = folder
                    updated.name = editedName.isEmpty ? folder.name : editedName
                    updated.emoji = editedEmoji.isEmpty ? "📁" : editedEmoji
                    updated.colorHex = editedColor.toHex()
                    updated.appBundleIDs = appBundleIDs
                    updated.stackPinned = editedStackPinned
                    updated.stackThreshold = editedStackThreshold
                    storage.updateFolder(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.isEmpty || hasErrors)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(selectedBundleID: $newBundleID)
        }
        .onChange(of: newBundleID) { _, newValue in
            if !newValue.isEmpty, !appBundleIDs.contains(newValue) {
                if let conflict = storage.folder(withBundleID: newValue, excluding: folder.id) {
                    bindingConflictError = "Already bound to \"\(conflict.name)\""
                } else {
                    bindingConflictError = nil
                    appBundleIDs.append(newValue)
                }
                newBundleID = ""
            }
        }
        .onChange(of: editedName) { _, newValue in
            if !newValue.isEmpty, storage.folderNameExists(newValue, excluding: folder.id) {
                nameError = "A folder with this name already exists."
            } else {
                nameError = nil
            }
        }
    }
    
    private var identitySection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                EmojiPickerButton(emoji: $editedEmoji)
                    .frame(width: 56, height: 56)
                    .background(editedColor.opacity(0.15))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Folder name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .medium))
                    if let err = nameError {
                        Text(err)
                            .font(.caption2).foregroundColor(.red)
                    }
                    HStack(spacing: 12) {
                        Text("Color:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        NativeColorPicker(color: $editedColor, width: 28, height: 28)
                            .frame(width: 28, height: 28)
                        
                        Spacer()
                        
                        Text("Tap emoji to change")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private var appBindingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("App Bindings", systemImage: "app.badge.fill")
                    .font(.system(size: 12, weight: .semibold))
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
                                        .frame(width: 14, height: 14)
                                }
                                Text(appName(for: bundleID))
                                    .font(.system(size: 11))
                                Button(action: { appBundleIDs.removeAll { $0 == bundleID } }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            if let err = bindingConflictError {
                Text(err)
                    .font(.caption2).foregroundColor(.red)
            }
        }
        .padding(14)
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func appName(for bundleID: String) -> String {
        NSWorkspace.shared.appDisplayName(forBundleID: bundleID)
    }
}

struct InstalledApp: Hashable {
    let name: String
    let bundleID: String
    let iconPath: String
}

struct AppPickerView: View {
    @Binding var selectedBundleID: String
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var installedApps: [InstalledApp] = []
    @State private var loadedIcons: [String: NSImage] = [:]
    private let loadedIconsSoftLimit: Int = 160
    
    private var filteredApps: [InstalledApp] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(10)
            
            Divider()
            
            List(filteredApps, id: \.bundleID) { app in
                Button(action: {
                    selectedBundleID = app.bundleID
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(nsImage: icon(for: app))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.system(size: 12, weight: .medium))
                            Text(app.bundleID).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 350, height: 400)
        .onAppear { loadApps() }
        .onDisappear { loadedIcons.removeAll() }
    }
    
    private func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let appDirs = [
                "/Applications",
                "/System/Applications",
                "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications"
            ]
            
            var apps: [InstalledApp] = []
            let fm = FileManager.default
            
            for dirPath in appDirs {
                let dirURL = URL(fileURLWithPath: dirPath)
                guard let enumerator = fm.enumerator(
                    at: dirURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                ) else { continue }
                
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" {
                        let infoPlist = fileURL.appendingPathComponent("Contents/Info.plist")
                        if let plist = NSDictionary(contentsOf: infoPlist),
                           let bundleID = plist["CFBundleIdentifier"] as? String {
                            let name = (plist["CFBundleName"] as? String)
                                ?? (plist["CFBundleDisplayName"] as? String)
                                ?? fileURL.deletingPathExtension().lastPathComponent
                            apps.append(InstalledApp(name: name, bundleID: bundleID, iconPath: fileURL.path))
                        }
                    }
                }
            }
            
            // De-duplicate by bundleID
            var uniqueApps: [String: InstalledApp] = [:]
            for app in apps {
                uniqueApps[app.bundleID] = app
            }
            let sortedApps = Array(uniqueApps.values).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.installedApps = sortedApps
            }
        }
    }

    private func icon(for app: InstalledApp) -> NSImage {
        if let cached = loadedIcons[app.iconPath] {
            return cached
        }

        if loadedIcons.count >= loadedIconsSoftLimit,
           let firstKey = loadedIcons.keys.first {
            loadedIcons.removeValue(forKey: firstKey)
        }

        let icon = NSWorkspace.shared.icon(forFile: app.iconPath)
        loadedIcons[app.iconPath] = icon
        return icon
    }
}

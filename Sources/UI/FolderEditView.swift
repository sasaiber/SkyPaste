import SwiftUI

struct FolderEditView: View {
    var folder: AppFolder
    @ObservedObject var storage: Storage
    @Environment(\.dismiss) var dismiss
    
    @State private var editedName: String
    @State private var editedEmoji: String
    @State private var editedColor: Color
    @State private var appBundleIDs: [String]
    
    @State private var newBundleID = ""
    @State private var showingAppPicker = false
    
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
                    var updated = folder
                    updated.name = editedName.isEmpty ? folder.name : editedName
                    updated.emoji = editedEmoji.isEmpty ? "📁" : editedEmoji
                    updated.colorHex = editedColor.toHex()
                    updated.appBundleIDs = appBundleIDs
                    storage.updateFolder(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.isEmpty)
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
                appBundleIDs.append(newValue)
                newBundleID = ""
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
        }
        .padding(14)
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
    }
    
    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let path = url.deletingLastPathComponent().lastPathComponent
            return path.hasSuffix(".app") ? String(path.dropLast(4)) : url.lastPathComponent
        }
        return bundleID
    }
}

struct AppPickerView: View {
    @Binding var selectedBundleID: String
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var installedApps: [(name: String, bundleID: String, icon: NSImage)] = []
    
    var filteredApps: [(name: String, bundleID: String, icon: NSImage)] {
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
                        Image(nsImage: app.icon)
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
    }
    
    private func loadApps() {
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        var apps: [(name: String, bundleID: String, icon: NSImage)] = []
        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let path = dir + "/" + item
                let infoPlist = path + "/Contents/Info.plist"
                if let plist = NSDictionary(contentsOfFile: infoPlist),
                   let bundleID = plist["CFBundleIdentifier"] as? String {
                    let name = (plist["CFBundleName"] as? String) ?? (plist["CFBundleDisplayName"] as? String) ?? item.replacingOccurrences(of: ".app", with: "")
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    apps.append((name: name, bundleID: bundleID, icon: icon))
                }
            }
        }
        
        apps.sort { $0.name < $1.name }
        installedApps = apps
    }
}

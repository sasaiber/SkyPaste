import SwiftUI
import UniformTypeIdentifiers

struct FoldersTabView: View {
    @ObservedObject var storage: Storage
    @Binding var folderShortcuts: [UUID: (key: String, mod: Int)]
    @Binding var folderMoveShortcuts: [UUID: (key: String, mod: Int)]
    @Binding var editingFolder: AppFolder?
    @Binding var folderToDelete: AppFolder?
    @Binding var showDeleteConfirmation: Bool
    var onValidate: ((String, Int, String) -> String?)?
    var onSaveShortcuts: () -> Void
    
    @State private var newFolderName = ""
    @State private var newFolderEmoji = "📁"
    @State private var newFolderColor = Color.accentColor
    
    var body: some View {
        VStack(spacing: 16) {
            if !storage.folders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Folders")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 2)
                    
                    ForEach(storage.folders) { folder in
                        folderRow(folder: folder)
                    }
                }
            } else {
                Text("No folders yet. Create one from the main window.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    private func folderRow(folder: AppFolder) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(Color(.tertiaryLabelColor))
                    .font(.system(size: 11))
                    .frame(width: 14)
                
                Button(action: { editingFolder = folder }) {
                    Text(folder.displayEmoji)
                        .font(.title3)
                        .frame(width: 28, height: 28)
                        .background(folder.displayColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(folder.displayColor.opacity(0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(folder.displayColor)
                    
                    HStack(spacing: 4) {
                        Text("\(storage.itemCount(forFolderID: folder.id)) items")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !folder.appBundleIDs.isEmpty {
                            Text("•").font(.caption2).foregroundColor(.secondary)
                            Text(folder.appBundleIDs.count == 1 ? (folder.appName ?? "App") : "\(folder.appBundleIDs.count) apps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { folderToDelete = folder; showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            HStack(spacing: 16) {
                ShortcutRow(label: "Open:", actionName: "Open '\(folder.name)'", key: folderShortcuts[folder.id]?.key ?? "", mod: folderShortcuts[folder.id]?.mod ?? 0) { k, m in
                    if !k.isEmpty {
                        for (fid, value) in folderShortcuts {
                            if fid != folder.id && value.key.lowercased() == k.lowercased() && value.mod == m {
                                folderShortcuts.removeValue(forKey: fid)
                            }
                        }
                    }
                    folderShortcuts[folder.id] = (k, m)
                    onSaveShortcuts()
                }
                
                ShortcutRow(label: "Move:", actionName: "Move to '\(folder.name)'", key: folderMoveShortcuts[folder.id]?.key ?? "", mod: folderMoveShortcuts[folder.id]?.mod ?? 0) { k, m in
                    if !k.isEmpty {
                        for (fid, value) in folderMoveShortcuts {
                            if fid != folder.id && value.key.lowercased() == k.lowercased() && value.mod == m {
                                folderMoveShortcuts.removeValue(forKey: fid)
                            }
                        }
                    }
                    folderMoveShortcuts[folder.id] = (k, m)
                    onSaveShortcuts()
                }
                
                Spacer()
                
                Button(action: { editingFolder = folder }) {
                    Label("Apps", systemImage: "app.badge.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 76)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
        .background(Color(.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .onDrag { NSItemProvider(object: folder.id.uuidString as NSString) }
        .onDrop(of: [.text], delegate: LibraryDropDelegate(folder: folder, storage: storage))
    }
    
    @ViewBuilder
    private func ShortcutRow(label: String, actionName: String, key: String, mod: Int, onSave: @escaping (String, Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 34, alignment: .trailing)
            ShortcutRecorder(actionName: actionName, keyString: Binding(get: { key }, set: { v in onSave(v, mod) }), modifiers: Binding(get: { mod }, set: { v in onSave(key, v) }), onValidate: onValidate, width: 80, isMinimalist: true)
        }
    }
}

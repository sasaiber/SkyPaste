import SwiftUI

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
    @State private var showEmojiPicker = false
    
    var body: some View {
        createSection
        listSection
    }
    
    @ViewBuilder
    private var createSection: some View {
        VStack(spacing: 16) {
            Text("Create Folder")
                .font(.headline)
            
            HStack(spacing: 12) {
                EmojiPickerButton(emoji: $newFolderEmoji)
                    .frame(width: 36, height: 36)
                
                ColorPicker("", selection: $newFolderColor).labelsHidden().frame(width: 30)
                
                TextField("Folder name...", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Spacer()
                Button("Create") {
                    storage.createFolder(
                        name: newFolderName.isEmpty ? "New Folder" : newFolderName,
                        emoji: newFolderEmoji.isEmpty ? "📁" : newFolderEmoji,
                        colorHex: newFolderColor.toHex()
                    )
                    newFolderName = ""
                    newFolderEmoji = "📁"
                    newFolderColor = .accentColor
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFolderName.isEmpty)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private var listSection: some View {
        if !storage.folders.isEmpty {
            Section("My Folders") {
                ForEach(storage.folders) { folder in
                    folderRow(folder: folder)
                }
            }
        }
    }
    
    @ViewBuilder
    private func folderRow(folder: AppFolder) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: { editingFolder = folder }) {
                Text(folder.displayEmoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(folder.displayColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Tap to edit")
            
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(folder.displayColor)
                Text("\(storage.itemCount(forFolderID: folder.id)) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                        Text("Open:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                    ShortcutRecorder(
                        actionName: "Open '\(folder.name)'",
                        keyString: Binding(
                            get: { folderShortcuts[folder.id]?.key ?? "" },
                            set: { val in
                                var curr = folderShortcuts[folder.id] ?? ("", 0)
                                curr.key = val
                                folderShortcuts[folder.id] = curr
                                onSaveShortcuts()
                            }
                        ),
                        modifiers: Binding(
                            get: { folderShortcuts[folder.id]?.mod ?? 0 },
                            set: { val in
                                var curr = folderShortcuts[folder.id] ?? ("", 0)
                                curr.mod = val
                                folderShortcuts[folder.id] = curr
                                onSaveShortcuts()
                            }
                        ),
                        onValidate: onValidate
                    )
                    .frame(width: 100)
                }
                
                HStack(alignment: .center, spacing: 8) {
                        Text("Move:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                    ShortcutRecorder(
                        actionName: "Move to '\(folder.name)'",
                        keyString: Binding(
                            get: { folderMoveShortcuts[folder.id]?.key ?? "" },
                            set: { val in
                                var curr = folderMoveShortcuts[folder.id] ?? ("", 0)
                                curr.key = val
                                folderMoveShortcuts[folder.id] = curr
                                onSaveShortcuts()
                            }
                        ),
                        modifiers: Binding(
                            get: { folderMoveShortcuts[folder.id]?.mod ?? 0 },
                            set: { val in
                                var curr = folderMoveShortcuts[folder.id] ?? ("", 0)
                                curr.mod = val
                                folderMoveShortcuts[folder.id] = curr
                                onSaveShortcuts()
                            }
                        ),
                        onValidate: onValidate
                    )
                    .frame(width: 100)
                }
            }
            
            Button(action: {
                folderToDelete = folder
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
        }
    }
}

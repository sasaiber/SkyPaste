import SwiftUI

struct FoldersTabView: View {
    @ObservedObject var storage: Storage
    @Binding var folderShortcuts: [UUID: (key: String, mod: Int)]
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
        Section("Create Folder") {
            HStack(alignment: .center, spacing: 8) {
                emojiPicker
                
                ColorPicker("", selection: $newFolderColor)
                    .labelsHidden()
                    .frame(width: 30, height: 30)
                
                TextField("Folder name...", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                
                Button("Add") {
                    storage.createFolder(
                        name: newFolderName,
                        emoji: newFolderEmoji.isEmpty ? "📁" : newFolderEmoji,
                        colorHex: newFolderColor.toHex()
                    )
                    newFolderName = ""
                    newFolderEmoji = "📁"
                    newFolderColor = .accentColor
                }
                .disabled(newFolderName.isEmpty)
            }
        }
    }
    
    @ViewBuilder
    private var emojiPicker: some View {
        Button(action: { showEmojiPicker = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(newFolderEmoji.isEmpty ? "📁" : newFolderEmoji)
                    .font(.title3)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEmojiPicker) {
            EmojiPickerView(selectedEmoji: $newFolderEmoji)
        }
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
                Text("\(storage.items.filter { $0.folderID == folder.id }.count) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            ShortcutRecorder(
                actionName: "Folder '\(folder.name)'",
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
            .frame(width: 80)
            .scaleEffect(0.9)
            
            Button(action: {
                folderToDelete = folder
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

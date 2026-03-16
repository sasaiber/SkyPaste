import SwiftUI

struct FolderEditView: View {
    var folder: AppFolder
    @ObservedObject var storage: Storage
    @Environment(\.dismiss) var dismiss
    
    @State private var editedName: String
    @State private var editedEmoji: String
    @State private var editedColor: Color
    
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
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Folder")
                .font(.headline)
                .padding(.top, 16)
            
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(editedColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(editedEmoji.isEmpty ? "📁" : editedEmoji)
                        .font(.largeTitle)
                        .frame(width: 52, height: 52)
                    // Invisible emoji picker overlay
                    TextField("", text: $editedEmoji)
                        .opacity(0.01)
                        .frame(width: 52, height: 52)
                        .onChange(of: editedEmoji) { _, newValue in
                            // Extract only emoji characters (preserving emoji with modifiers)
                            let emojiCharacters = newValue.filter { char in
                                char.unicodeScalars.allSatisfy { $0.properties.isEmoji }
                            }
                            
                            if !emojiCharacters.isEmpty {
                                // Keep only the last emoji
                                if let lastEmoji = emojiCharacters.last {
                                    editedEmoji = String(lastEmoji)
                                }
                            } else if newValue.isEmpty {
                                // Allow clearing the field
                                editedEmoji = ""
                            } else {
                                // User entered non-emoji text, keep previous value
                                editedEmoji = folder.emoji ?? "📁"
                            }
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Folder name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    
                    HStack {
                        ColorPicker("Color:", selection: $editedColor)
                            .labelsHidden()
                        Text("Tap the emoji to change it")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    var updated = folder
                    updated.name = editedName.isEmpty ? folder.name : editedName
                    updated.emoji = editedEmoji.isEmpty ? "📁" : editedEmoji
                    updated.colorHex = editedColor.toHex()
                    storage.updateFolder(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.isEmpty)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 340)
    }
}

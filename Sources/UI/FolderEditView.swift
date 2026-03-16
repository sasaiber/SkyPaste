import SwiftUI

struct FolderEditView: View {
    var folder: AppFolder
    @ObservedObject var storage: Storage
    @Environment(\.dismiss) var dismiss
    
    @State private var editedName: String
    @State private var editedEmoji: String
    @State private var editedColor: Color
    @State private var showEmojiPicker = false
    
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
                }
                .frame(width: 52, height: 52)
                .onTapGesture {
                    showEmojiPicker = true
                }
                .popover(isPresented: $showEmojiPicker) {
                    EmojiPickerView(selectedEmoji: $editedEmoji)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Folder name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    
                    HStack {
                        ColorPicker("Color:", selection: $editedColor)
                            .labelsHidden()
                        Text("Tap emoji to change")
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

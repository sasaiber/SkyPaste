import SwiftUI
import AppKit

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) var dismiss
    
    @State private var pastedEmoji = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose an Emoji")
                .font(.headline)
            
            VStack(spacing: 12) {
                Button(action: openSystemEmojiPicker) {
                    HStack {
                        Image(systemName: "face.smiling")
                        Text("Open System Emoji Panel")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Ctrl+Cmd+Space to open emoji picker")
                
                Divider()
                
                Text("Or paste emoji here:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Paste emoji...", text: $pastedEmoji)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pastedEmoji) { _, newValue in
                        // Extract emoji from pasted text
                        let emojis = newValue.filter { char in
                            char.unicodeScalars.allSatisfy { $0.properties.isEmoji }
                        }
                        if let firstEmoji = emojis.first {
                            selectedEmoji = String(firstEmoji)
                            pastedEmoji = ""
                            dismiss()
                        }
                    }
            }
            .padding()
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 340, height: 220)
    }
    
    private func openSystemEmojiPicker() {
        // Open macOS system emoji picker
        NSApplication.shared.orderFrontCharacterPalette(nil)
    }
}

import SwiftUI

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) var dismiss
    
    // Popular emojis for quick selection
    let popularEmojis = [
        "📁", "📂", "📋", "📝", "📄", "📃", "📑", "📊", "📈", "📉",
        "🎯", "🎨", "🎭", "🎪", "🎬", "🎲", "🎮", "🎰", "🎳",
        "💼", "💻", "🖥️", "⌨️", "🖱️", "🖨️", "📱", "☎️", "📞",
        "📧", "💌", "📮", "📬", "📭", "📪", "🗳️", "✉️", "📨",
        "🔐", "🔒", "🔓", "🔑", "🗝️", "🔓", "🔏", "🔐",
        "⭐", "🌟", "✨", "💫", "⚡", "🔥", "💥", "💢", "💯",
        "📚", "📖", "📕", "📗", "📘", "📙", "📓", "📔",
        "🎓", "🎒", "📐", "📏", "📌", "📍", "📎", "🖇️", "📝",
        "🏆", "🥇", "🥈", "🥉", "🎖️", "🏅", "🎗️",
        "🎉", "🎊", "🎈", "🎀", "🎁", "🎂", "🍰",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎",
        "💻", "⚙️", "🔧", "🔨", "⚒️", "🛠️", "🔩", "⚙️",
        "🌍", "🌎", "🌏", "🗺️", "🧭", "📍",
        "🚀", "🛸", "🛰️", "📡", "🔭", "🔬",
        "🎵", "🎶", "🎼", "🎹", "🎸", "🎺", "🎷", "🥁"
    ]
    
    @State private var searchText = ""
    
    var filteredEmojis: [String] {
        if searchText.isEmpty {
            return popularEmojis
        }
        return [searchText.first.map { String($0) } ?? ""].filter { !$0.isEmpty }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Choose an Emoji")
                .font(.headline)
            
            TextField("Search or paste emoji", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 8) {
                    ForEach(filteredEmojis, id: \.self) { emoji in
                        Button(action: {
                            selectedEmoji = emoji
                            dismiss()
                        }) {
                            Text(emoji)
                                .font(.title2)
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Select \(emoji)")
                    }
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 360, height: 420)
    }
}

import SwiftUI
import AppKit

struct AboutTabView: View {
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    var body: some View {
        Section {
            VStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 4) {
                    Text("SkyPaste")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("A lightweight clipboard manager for macOS.\nBuilt for personal convenience — fast, private, and clutter-free.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 340)

                HStack(spacing: 12) {
                    Link("⭐ Star on GitHub", destination: URL(string: "https://github.com/")!)
                    Text("·").foregroundColor(.secondary)
                    Link("🎮 Steam Wishlist", destination: URL(string: "https://steamcommunity.com/id/sasaiber/")!)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

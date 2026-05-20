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
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                Text("SkyPaste")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("A lightweight clipboard manager for macOS.\nBuilt for personal convenience — fast, private, and clutter-free.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 340)
                
                HStack(spacing: 12) {
                    if let ghURL = URL(string: "https://github.com/sasaiber/SkyPaste") {
                        Link("⭐ Star on GitHub", destination: ghURL)
                    }
                    Text("·").foregroundColor(.secondary)
                    if let steamURL = URL(string: "https://steamcommunity.com/id/sasaiber/") {
                        Link(" Steam Wishlist", destination: steamURL)
                    }
                }
                .font(.caption)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Updates")
                    .font(.headline)
                
                HStack {
                    Text("Automatically checks for updates in the background.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        AppDelegate.shared.checkForUpdates()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Check Now")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding()
    }
}

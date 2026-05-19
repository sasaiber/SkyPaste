import SwiftUI
import AppKit
import UserNotifications

struct AboutTabView: View {
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
    
    @StateObject private var updateChecker = UpdateChecker.shared
    
    @AppStorage("updateCheckFrequency") private var updateCheckFrequencyRaw: String = UpdateCheckFrequency.daily.rawValue
    
    private var frequency: Binding<UpdateCheckFrequency> {
        Binding(
            get: { UpdateCheckFrequency(rawValue: self.updateCheckFrequencyRaw) ?? .every3Days },
            set: { self.updateCheckFrequencyRaw = $0.rawValue }
        )
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
                
                Text("Version 1.0.1")
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
                    Text("Check for Updates:")
                    Spacer()
                    Picker("", selection: frequency) {
                        ForEach(UpdateCheckFrequency.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(width: 110)
                    
                    Button(action: {
                        Task { await updateChecker.checkForUpdates() }
                    }) {
                        if updateChecker.isChecking {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Check Now")
                    }
                    .disabled(updateChecker.isChecking || updateChecker.isDownloading || updateChecker.isInstalling)
                }
                
                if updateChecker.updateAvailable && !updateChecker.isDownloading && !updateChecker.isInstalling {
                    Button(action: {
                        Task { await updateChecker.downloadAndInstall() }
                    }) {
                        Label("Download & Install Update", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                
                if updateChecker.isDownloading || updateChecker.isInstalling {
                    VStack(spacing: 8) {
                        ProgressView(value: updateChecker.downloadProgress)
                            .progressViewStyle(.linear)
                        Text(updateChecker.isDownloading ? "Downloading update..." : "Installing... App will restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if updateChecker.hasError {
                    Text("Error: \(updateChecker.errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if updateChecker.updateAvailable && !updateChecker.isDownloading && !updateChecker.isInstalling {
                    if let releaseURL = URL(string: updateChecker.releaseURL) {
                        Link("View Release Notes →", destination: releaseURL)
                            .font(.caption)
                    }
                } else if !updateChecker.isChecking && !updateChecker.hasError {
                    Text("You're up to date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding()
    }
}

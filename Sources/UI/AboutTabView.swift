import SwiftUI
import AppKit
import Sparkle

enum UpdateFrequency: Int, CaseIterable, Identifiable {
    case off = 0
    case daily = 86400
    case every3Days = 259200
    case weekly = 604800
    
    var id: Int { self.rawValue }
    
    var title: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Every Day"
        case .every3Days: return "Every 3 Days"
        case .weekly: return "Every Week"
        }
    }
}

struct AboutTabView: View {
    @AppStorage("SUEnableAutomaticChecks") private var enableAutomaticChecks: Bool = true
    @AppStorage("SUScheduledCheckInterval") private var scheduledCheckInterval: Int = 86400
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyUpdate: Bool = false
    
    private var frequency: Binding<UpdateFrequency> {
        Binding(
            get: {
                if !self.enableAutomaticChecks { return .off }
                return UpdateFrequency(rawValue: self.scheduledCheckInterval) ?? .daily
            },
            set: { newValue in
                if newValue == .off {
                    self.enableAutomaticChecks = false
                } else {
                    self.enableAutomaticChecks = true
                    self.scheduledCheckInterval = newValue.rawValue
                }
            }
        )
    }
    
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
                    Text("Check for updates:")
                        .font(.body)
                    
                    Picker("", selection: frequency) {
                        ForEach(UpdateFrequency.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    
                    Spacer()
                    
                    Button(action: {
                        AppDelegate.shared.checkForUpdates()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Check Now")
                    }
                }
                
                Toggle("Automatically download and install updates", isOn: $automaticallyUpdate)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding()
    }
}

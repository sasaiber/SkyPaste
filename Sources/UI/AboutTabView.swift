import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

struct AboutTabView: View {
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
    
    @State private var showUninstallConfirm = false
    @State private var uninstallCountdown = 5
    @State private var uninstallTimer: Timer?
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
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Uninstaller")
                    .font(.headline)
                
                Button("Uninstall SkyPaste & Reset Everything", role: .destructive) {
                    showUninstallConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Text("Resets all permissions, removes login item + every file/folder. Fresh install experience on next launch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showUninstallConfirm) {
            VStack(spacing: 16) {
                Text("Uninstall SkyPaste?")
                    .font(.headline)
                
                Text("This will permanently delete all clipboard history, custom folders, shortcuts, reset permissions, remove login item, and erase all app files. This cannot be undone.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 280)
                
                if uninstallCountdown > 0 {
                    Text("You can confirm in \(uninstallCountdown)s")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text("You can now confirm uninstall")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        uninstallTimer?.invalidate()
                        showUninstallConfirm = false
                    }
                    
                    Button("Uninstall", role: .destructive) {
                        performUninstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(uninstallCountdown > 0)
                }
            }
            .padding(20)
            .frame(width: 340)
            .onAppear {
                uninstallCountdown = 5
                uninstallTimer?.invalidate()
                uninstallTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    if uninstallCountdown > 0 {
                        uninstallCountdown -= 1
                    } else {
                        timer.invalidate()
                    }
                }
            }
        }
    }
    
    private func performUninstall() {
        let appPath = Bundle.main.bundlePath
        let bundleID = "com.skytech.macvision"
        
        try? SMAppService.mainApp.unregister()
        
        let script = """
        sleep 2
        
        /usr/bin/tccutil reset All \(bundleID) 2>/dev/null || true
        /usr/bin/tccutil reset Accessibility \(bundleID) 2>/dev/null || true
        /usr/bin/tccutil reset Notifications \(bundleID) 2>/dev/null || true
        /usr/bin/tccutil reset SystemPolicyAllFiles \(bundleID) 2>/dev/null || true
        sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db "DELETE FROM access WHERE client LIKE '%sky%' OR client LIKE '%skypaste%' OR client LIKE '%\(bundleID)%';" 2>/dev/null || true
        sqlite3 /Library/Application\\ Support/com.apple.TCC/TCC.db "DELETE FROM access WHERE client LIKE '%sky%' OR client LIKE '%skypaste%' OR client LIKE '%\(bundleID)%';" 2>/dev/null || true
        rm -f /Library/Application\\ Support/com.apple.TCC/AdhocSignatureCache/* 2>/dev/null || true
        rm -f ~/Library/Application\\ Support/com.apple.TCC/AdhocSignatureCache/* 2>/dev/null || true
        killall -HUP cfprefsd 2>/dev/null || true
        rm -rf ~/Library/Application\\ Support/SkyPaste ~/Library/Application\\ Support/com.sky* 2>/dev/null || true
        rm -rf ~/Library/Caches/SkyPaste ~/Library/Caches/com.sky* 2>/dev/null || true
        rm -rf ~/Library/Logs/SkyPaste ~/Library/Logs/com.sky* 2>/dev/null || true
        rm -rf ~/.SkyPaste 2>/dev/null || true
        rm -rf ~/Library/Preferences/com.sky* ~/Library/Preferences/com.sky.skypaste* ~/Library/Preferences/\(bundleID)* 2>/dev/null || true
        rm -rf ~/Library/Containers/com.sky* ~/Library/Containers/\(bundleID)* 2>/dev/null || true
        /usr/bin/defaults delete \(bundleID) 2>/dev/null || true
        /bin/launchctl remove \(bundleID) 2>/dev/null || true
        rm -f ~/Library/LaunchAgents/\(bundleID)*.plist 2>/dev/null || true
        
        sleep 1
        
        /bin/rm -rf "\(appPath)"
        """
        
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", script]
        try? process.run()
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        exit(0)
    }
}

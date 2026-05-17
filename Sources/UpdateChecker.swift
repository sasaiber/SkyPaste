import Foundation
import AppKit
import os

enum UpdateCheckFrequency: String, Codable, CaseIterable {
    case off = "Off"
    case daily = "Every Day"
    case every3Days = "Every 3 Days"
    case weekly = "Every Week"
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    let publishedAt: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var releaseURL = ""
    @Published var hasError = false
    @Published var errorMessage = ""
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isInstalling = false
    
    private let repoOwner = "sasaiber"
    private let repoName = "SkyPaste"
    private let logger = Logger(subsystem: "com.skytech.macvision", category: "UpdateChecker")
    
    private var zipDownloadURL: String?
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }
    
    var frequency: UpdateCheckFrequency {
        get {
            if let raw = UserDefaults.standard.string(forKey: "updateCheckFrequency"),
               let value = UpdateCheckFrequency(rawValue: raw) {
                return value
            }
            return .daily
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "updateCheckFrequency")
        }
    }
    
    var autoCheckEnabled: Bool {
        frequency != .off
    }
    
    private var lastCheckDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastUpdateCheckDate")
        }
    }
    
    func shouldAutoCheck() -> Bool {
        guard autoCheckEnabled else { return false }
        guard let lastCheck = lastCheckDate else { return true }
        
        let interval: TimeInterval
        switch frequency {
        case .off: return false
        case .daily: interval = 86_400
        case .every3Days: interval = 86_400 * 3
        case .weekly: interval = 86_400 * 7
        }
        
        return Date().timeIntervalSince(lastCheck) >= interval
    }
    
    func checkForUpdates() async {
        isChecking = true
        hasError = false
        errorMessage = ""
        updateAvailable = false
        zipDownloadURL = nil
        
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 404 {
                logger.info("No releases found on GitHub repo")
                isChecking = false
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestTag = release.tagName.replacingOccurrences(of: "v", with: "")
            
            lastCheckDate = Date()
            
            if isVersionNewer(latestTag, than: currentVersion) {
                updateAvailable = true
                latestVersion = latestTag
                releaseNotes = release.body
                releaseURL = release.htmlUrl
                
                if let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
                    zipDownloadURL = zipAsset.browserDownloadUrl
                } else {
                    zipDownloadURL = "https://github.com/\(repoOwner)/\(repoName)/archive/refs/tags/\(release.tagName).zip"
                }
                
                logger.info("Update available: \(latestTag)")
            } else {
                logger.info("Already on latest version: \(self.currentVersion)")
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            logger.error("Update check failed: \(error.localizedDescription)")
        }
        
        isChecking = false
    }
    
    func downloadAndInstall() async {
        guard let zipURLString = zipDownloadURL, let zipURL = URL(string: zipURLString) else {
            hasError = true
            errorMessage = "No download URL available"
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        hasError = false
        errorMessage = ""
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SkyPasteUpdate")
        let zipFileURL = tempDir.appendingPathComponent("update.zip")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            var request = URLRequest(url: zipURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let (tempFileURL, response) = try await URLSession.shared.download(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            try FileManager.default.moveItem(at: tempFileURL, to: zipFileURL)
            downloadProgress = 0.5
            
            isDownloading = false
            isInstalling = true
            
            let extractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            try extractZip(zipFileURL, to: extractDir)
            downloadProgress = 0.75
            
            guard let newAppURL = findAppBundle(in: extractDir) else {
                throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not find SkyPaste.app in the update package"])
            }
            
            let currentAppURL = Bundle.main.bundleURL
            let scriptPath = tempDir.appendingPathComponent("update.sh").path
            
            let script = """
            #!/bin/bash
            sleep 2
            
            OLD_APP="\(currentAppURL.path)"
            NEW_APP="\(newAppURL.path)"
            
            rm -rf "$OLD_APP"
            cp -R "$NEW_APP" "$OLD_APP"
            
            if [ $? -eq 0 ]; then
                open "$OLD_APP"
            fi
            
            rm -rf "\(tempDir.path)"
            """
            
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = [scriptPath]
            try process.run()
            
            downloadProgress = 1.0
            NSApplication.shared.terminate(nil)
            
        } catch {
            isDownloading = false
            isInstalling = false
            hasError = true
            errorMessage = "Installation failed: \(error.localizedDescription)"
            logger.error("Update installation failed: \(error.localizedDescription)")
            
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    private func extractZip(_ zipURL: URL, to destination: URL) throws {
        let process = Process()
        process.launchPath = "/usr/bin/ditto"
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown extraction error"
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update: \(errorMsg)"])
        }
    }
    
    private func findAppBundle(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        
        if let appURL = findAppRecursive(in: directory, fileManager: fileManager) {
            return appURL
        }
        
        return nil
    }
    
    private func findAppRecursive(in directory: URL, fileManager: FileManager) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "app" {
                return fileURL
            }
        }
        
        return nil
    }
    
    private func isVersionNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        let maxComponents = max(newComponents.count, currentComponents.count)
        
        for i in 0..<maxComponents {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        
        return false
    }
}

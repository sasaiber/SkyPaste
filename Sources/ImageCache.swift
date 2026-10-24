import Foundation
import AppKit
import UniformTypeIdentifiers

class ImageCache {
    static let shared = ImageCache()
    
    // NSCache automatically handles memory pressure and eviction natively
    private let cache = NSCache<NSURL, NSImage>()
    private var negativeAppIconBundleIDs = Set<String>()
    private var appDisplayNames: [String: String] = [:]
    private let isDirectoryCache = NSCache<NSString, NSNumber>()
    
    init() {
        // Bound both item count and memory pressure behavior.
        cache.countLimit = 150
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64 MB
    }
    
    func image(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func setImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: estimatedCost(for: image))
    }
    
    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
    
    func clear() {
        cache.removeAllObjects()
    }

    private func estimatedCost(for image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        let pixels = rep.pixelsWide * rep.pixelsHigh
        return max(0, pixels * 4) // RGBA bytes estimate
    }
    
    func fastAppIcon(bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        if negativeAppIconBundleIDs.contains(bundleID) { return nil }
        let cacheKey = URL(string: "appicon://\(bundleID)")!
        if let cached = image(for: cacheKey) {
            return cached
        }
        var icon: NSImage? = nil
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        if let icon = icon {
            setImage(icon, for: cacheKey)
        } else {
            negativeAppIconBundleIDs.insert(bundleID)
        }
        return icon
    }

    func appDisplayName(forBundleID bundleID: String) -> String? {
        if let cached = appDisplayNames[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let path = url.deletingLastPathComponent().lastPathComponent
        let name = path.hasSuffix(".app") ? String(path.dropLast(4)) : url.lastPathComponent
        appDisplayNames[bundleID] = name
        return name
    }

    func isDirectory(at url: URL) -> Bool {
        let key = url.path as NSString
        if let cached = isDirectoryCache.object(forKey: key) {
            return cached.boolValue
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        isDirectoryCache.setObject(NSNumber(value: isDir.boolValue), forKey: key)
        return isDir.boolValue
    }

    func fastFileIcon(for url: URL) -> NSImage {
        let ext = url.pathExtension.isEmpty ? "default" : url.pathExtension.lowercased()
        let cacheKey = URL(string: "fileicon://\(ext)")!
        if let cached = image(for: cacheKey) {
            return cached
        }
        let type = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        setImage(icon, for: cacheKey)
        return icon
    }

    // Async helpers for row optimization
    func asyncAppIcon(bundleID: String?, completion: @escaping (NSImage?) -> Void) {
        if let cached = fastAppIcon(bundleID: bundleID) {
            completion(cached)
            return
        }
        guard let bundleID = bundleID else {
            completion(nil)
            return
        }
        
        let cacheKey = URL(string: "appicon://\(bundleID)")!
        
        DispatchQueue.global(qos: .utility).async {
            var icon: NSImage? = nil
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                icon = NSWorkspace.shared.icon(forFile: "/Applications/\(bundleID).app")
            }
            DispatchQueue.main.async {
                if let icon = icon {
                    self.setImage(icon, for: cacheKey)
                }
                completion(icon)
            }
        }
    }
    
    func asyncFileIcon(url: URL, completion: @escaping (NSImage?) -> Void) {
        let icon = fastFileIcon(for: url)
        completion(icon)
    }
    
    func asyncThumbnail(url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = image(for: url) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                if let image = image {
                    self.setImage(image, for: url)
                }
                completion(image)
            }
        }
    }
}

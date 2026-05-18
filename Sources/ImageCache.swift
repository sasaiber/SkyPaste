import Foundation
import AppKit

class ImageCache {
    static let shared = ImageCache()
    
    private var cache: [URL: NSImage] = [:]
    private var accessOrder: [URL] = [] // LRU order
    private let lock = NSLock()
    private let maxCacheSize = 100 * 1024 * 1024 // 100 MB
    private var currentCacheSize = 0
    
    func image(for url: URL) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        
        if cache[url] != nil {
            // Move to most recently used
            accessOrder.removeAll { $0 == url }
            accessOrder.append(url)
        }
        return cache[url]
    }
    
    func setImage(_ image: NSImage, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        let size = image.tiffRepresentation?.count ?? 0
        
        // Remove from order if exists (to move to end)
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
        
        cache[url] = image
        currentCacheSize += size
        
        // LRU eviction
        while currentCacheSize > maxCacheSize && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            if let imgSize = cache[oldest]?.tiffRepresentation?.count {
                currentCacheSize -= imgSize
            }
            cache.removeValue(forKey: oldest)
        }
    }
    
    func removeImage(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        if let size = cache[url]?.tiffRepresentation?.count {
            currentCacheSize -= size
        }
        accessOrder.removeAll { $0 == url }
        cache.removeValue(forKey: url)
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        accessOrder.removeAll()
        currentCacheSize = 0
    }
    
    // Async helpers for row optimization
    func asyncAppIcon(bundleID: String?, completion: @escaping (NSImage?) -> Void) {
        guard let bundleID = bundleID else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let icon = NSWorkspace.shared.icon(forFile: "/Applications/\(bundleID).app")
            DispatchQueue.main.async {
                completion(icon)
            }
        }
    }
    
    func asyncThumbnail(url: URL, completion: @escaping (NSImage?) -> Void) {
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

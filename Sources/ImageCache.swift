import Foundation
import AppKit

class ImageCache {
    static let shared = ImageCache()
    
    private var cache: [URL: NSImage] = [:]
    private let lock = NSLock()
    private let maxCacheSize = 100 * 1024 * 1024 // 100 MB
    private var currentCacheSize = 0
    
    func image(for url: URL) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[url]
    }
    
    func setImage(_ image: NSImage, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        let size = image.tiffRepresentation?.count ?? 0
        cache[url] = image
        currentCacheSize += size
        
        // Evict oldest items if cache too large
        if currentCacheSize > maxCacheSize {
            let toRemove = cache.count / 2
            for (i, url) in cache.keys.enumerated() {
                if i >= toRemove { break }
                if let imgSize = cache[url]?.tiffRepresentation?.count {
                    currentCacheSize -= imgSize
                }
                cache.removeValue(forKey: url)
            }
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        currentCacheSize = 0
    }
    
    func removeImage(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        if let size = cache[url]?.tiffRepresentation?.count {
            currentCacheSize -= size
        }
        cache.removeValue(forKey: url)
    }
}

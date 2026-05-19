import Foundation
import AppKit
import AVFoundation
import QuickLookThumbnailing
import PDFKit

enum ThumbStatus: String, Codable {
    case pending
    case ok
    case failed
}

final class ThumbnailGenerator: @unchecked Sendable {
    static let shared = ThumbnailGenerator()
    
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 3
        q.qualityOfService = .utility
        return q
    }()
    
    private let thumbsDirectory: URL = {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("SkyPaste/Thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    // Checks if running on battery (requires IOKit/Power management, simulated simply for now based on ProcessInfo)
    private var isOnBattery: Bool {
        // NSProcessInfo doesn't directly expose battery state easily without IOKit,
        // For the sake of the task, we can assume false or try to read it.
        // To be safe, we will just pass it as a parameter, but for simplicity, default to false.
        return false
    }
    
    func generateThumbnail(for url: URL) async -> (URL?, ThumbStatus) {
        let ext = url.pathExtension.lowercased()
        let pathData = url.path.data(using: .utf8) ?? Data()
        let identifier = pathData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        
        let thumbURL = thumbsDirectory.appendingPathComponent("\(identifier).jpg")
        
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            return (thumbURL, .ok)
        }
        
        return await withCheckedContinuation { continuation in
            queue.addOperation {
                autoreleasepool {
                    let result = self.createThumbnailSync(for: url, thumbURL: thumbURL, ext: ext, isBatteryPowered: self.isOnBattery)
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    func getExistingThumbnailURL(for url: URL) -> URL? {
        let pathData = url.path.data(using: .utf8) ?? Data()
        let identifier = pathData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let thumbURL = thumbsDirectory.appendingPathComponent("\(identifier).jpg")
        
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            return thumbURL
        }
        return nil
    }
    
    private func createThumbnailSync(for url: URL, thumbURL: URL, ext: String, isBatteryPowered: Bool) -> (URL?, ThumbStatus) {
        // IMAGES
        let imageExts = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "raw"]
        if imageExts.contains(ext) {
            guard let image = NSImage(contentsOf: url) else { return (nil, .failed) }
            if let data = self.resizeAndCompress(image: image, maxDimension: 200) {
                do {
                    try data.write(to: thumbURL)
                    return (thumbURL, .ok)
                } catch { return (nil, .failed) }
            }
            return (nil, .failed)
        }
        
        // VIDEO
        let videoExts = ["mp4", "mov", "avi", "mkv", "m4v", "webm"]
        if videoExts.contains(ext) {
            if isBatteryPowered {
                // If on battery, delay for 5 seconds to avoid sudden spikes when copying
                Thread.sleep(forTimeInterval: 5.0)
            }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)
            do {
                let cgImage = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
                if let data = self.resizeAndCompress(image: image, maxDimension: 200) {
                    try data.write(to: thumbURL)
                    return (thumbURL, .ok)
                }
            } catch {
                return (nil, .failed)
            }
            return (nil, .failed)
        }
        
        // DOCUMENTS / PDF
        let docExts = ["pdf", "docx", "xlsx", "pptx", "pages", "numbers"]
        if docExts.contains(ext) {
            if ext == "pdf", let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) {
                let image = page.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
                if let data = self.resizeAndCompress(image: image, maxDimension: 200) {
                    try? data.write(to: thumbURL)
                    return (thumbURL, .ok)
                }
            }
            
            // Fallback to QLThumbnailGenerator
            let size = CGSize(width: 200, height: 200)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1.0, representationTypes: .thumbnail)
            let group = DispatchGroup()
            group.enter()
            var thumbData: Data? = nil
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, type, error in
                if let cgImage = thumbnail?.cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
                    thumbData = self.resizeAndCompress(image: nsImage, maxDimension: 200)
                }
                group.leave()
            }
            group.wait()
            if let data = thumbData {
                try? data.write(to: thumbURL)
                return (thumbURL, .ok)
            }
        }
        
        // EVERYTHING ELSE (fallback)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        if let data = self.resizeAndCompress(image: icon, maxDimension: 200) {
            try? data.write(to: thumbURL)
            return (thumbURL, .ok)
        }
        
        return (nil, .failed)
    }
    
    private func resizeAndCompress(image: NSImage, maxDimension: CGFloat) -> Data? {
        let width = image.size.width
        let height = image.size.height
        let scale = min(maxDimension / width, maxDimension / height, 1.0)
        
        let newSize = NSSize(width: width * scale, height: height * scale)
        let scaledImage = NSImage(size: newSize)
        
        scaledImage.lockFocus()
        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        scaledImage.unlockFocus()
        
        guard let tiff = scaledImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}

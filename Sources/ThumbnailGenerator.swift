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

    private let imageExts = Set(["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "raw"])
    private let videoExts = Set(["mp4", "mov", "avi", "mkv", "m4v", "webm"])
    private let docExts = Set(["pdf", "docx", "xlsx", "pptx", "pages", "numbers"])
    
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
    
    private let existingThumbsCache = NSCache<NSURL, NSNumber>()

    func generateThumbnail(for url: URL) async -> (URL?, ThumbStatus) {
        let ext = url.pathExtension.lowercased()
        let thumbURL = thumbnailURL(for: url)

        let alreadyExists = existingThumbsCache.object(forKey: thumbURL as NSURL)?.boolValue == true

        if alreadyExists || FileManager.default.fileExists(atPath: thumbURL.path) {
            existingThumbsCache.setObject(true as NSNumber, forKey: thumbURL as NSURL)
            return (thumbURL, .ok)
        }

        let result: (URL?, ThumbStatus)
        if imageExts.contains(ext) || videoExts.contains(ext) {
            result = await withCheckedContinuation { continuation in
                queue.addOperation {
                    autoreleasepool {
                        let res = self.createThumbnailSync(for: url, thumbURL: thumbURL, ext: ext, isBatteryPowered: self.isOnBattery)
                        continuation.resume(returning: res)
                    }
                }
            }
        } else if docExts.contains(ext), let docResult = await createDocumentThumbnail(for: url, thumbURL: thumbURL, ext: ext) {
            result = docResult
        } else {
            result = await withCheckedContinuation { continuation in
                queue.addOperation {
                    autoreleasepool {
                        let res = self.createFallbackIconThumbnail(for: url, thumbURL: thumbURL)
                        continuation.resume(returning: res)
                    }
                }
            }
        }

        if result.1 == .ok {
            existingThumbsCache.setObject(true as NSNumber, forKey: thumbURL as NSURL)
        }
        return result
    }
    
    func getExistingThumbnailURL(for url: URL) -> URL? {
        let thumbURL = thumbnailURL(for: url)

        if existingThumbsCache.object(forKey: thumbURL as NSURL)?.boolValue == true {
            return thumbURL
        }

        if FileManager.default.fileExists(atPath: thumbURL.path) {
            existingThumbsCache.setObject(true as NSNumber, forKey: thumbURL as NSURL)
            return thumbURL
        }
        return nil
    }

    private func thumbnailURL(for url: URL) -> URL {
        let pathData = url.path.data(using: .utf8) ?? Data()
        let identifier = pathData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return thumbsDirectory.appendingPathComponent("\(identifier).jpg")
    }
    
    private func createThumbnailSync(for url: URL, thumbURL: URL, ext: String, isBatteryPowered: Bool) -> (URL?, ThumbStatus) {
        // IMAGES
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

        return createFallbackIconThumbnail(for: url, thumbURL: thumbURL)
    }

    private func createFallbackIconThumbnail(for url: URL, thumbURL: URL) -> (URL?, ThumbStatus) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        if let data = self.resizeAndCompress(image: icon, maxDimension: 200) {
            try? data.write(to: thumbURL)
            return (thumbURL, .ok)
        }

        return (nil, .failed)
    }

    private func createDocumentThumbnail(for url: URL, thumbURL: URL, ext: String) async -> (URL?, ThumbStatus)? {
        if ext == "pdf", let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
            if let data = self.resizeAndCompress(image: image, maxDimension: 200) {
                try? data.write(to: thumbURL)
                return (thumbURL, .ok)
            }
        }

        let size = CGSize(width: 200, height: 200)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1.0, representationTypes: .thumbnail)

        if let data = await generateQuickLookData(for: request) {
            try? data.write(to: thumbURL)
            return (thumbURL, .ok)
        }

        return nil
    }

    private func generateQuickLookData(for request: QLThumbnailGenerator.Request) async -> Data? {
        await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, _, _ in
                guard let cgImage = thumbnail?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
                let data = self.resizeAndCompress(image: nsImage, maxDimension: 200)
                continuation.resume(returning: data)
            }
        }
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

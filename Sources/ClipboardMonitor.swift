import Foundation
import AppKit
import UniformTypeIdentifiers

class ClipboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    let storage: Storage

    init(storage: Storage) {
        self.storage = storage
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.75,
            repeats: true
        ) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        processNewItem()
    }

    private func processNewItem() {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let allItems = pasteboard.pasteboardItems ?? []
        let types = Set(pasteboard.types ?? [])

        // 1. Multi-file / single-file: collect ALL file URLs from every pasteboard item
        let fileURLs: [URL] = allItems.compactMap { pbItem in
            guard let data = pbItem.data(forType: .fileURL),
                  let str = String(data: data, encoding: .utf8),
                  let url = URL(string: str) else { return nil }
            return url
        }

        if !fileURLs.isEmpty {
            // Store all files as a single clipboard item
            let item = ClipboardItem(
                timestamp: Date(), 
                firstCopiedAt: Date(), 
                type: .file,
                textContent: fileURLs.map { $0.absoluteString }.joined(separator: "\n"),
                title: fileURLs.count > 1 ? "\(fileURLs.count) files" : fileURLs.first?.lastPathComponent,
                fileURL: fileURLs.first,
                appSource: sourceApp, 
                appBundleID: sourceBundleID
            )
            Task { @MainActor in storage.addItem(item) }
            return
        }

        // 2. Images — read raw PNG/TIFF bytes, write to disk immediately
        // Handle multiple images at once - check ALL pasteboard items
        var imageURLs: [URL] = []
        
        for pbItem in allItems {
            // Try PNG first
            if let pngData = pbItem.data(forType: .png) {
                if let url = savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                    imageURLs.append(url)
                }
            }
            // Try TIFF
            else if let tiffData = pbItem.data(forType: .tiff) {
                if let pngData = extractPNGFromTIFF(tiffData) {
                    if let url = savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                        imageURLs.append(url)
                    }
                }
            }
        }
        
        // Fallback: try NSImage if we got nothing from items
        if imageURLs.isEmpty && (types.contains(.tiff) || types.contains(.png)),
           NSImage.canInit(with: pasteboard),
           let image = NSImage(pasteboard: pasteboard),
           let data = renderImageToPNG(image) {
            if let url = savePNGToDiskAndReturnURL(data: data, source: sourceApp, bundleID: sourceBundleID) {
                imageURLs.append(url)
            }
        }
        
        if !imageURLs.isEmpty {
            // Create item(s) for images
            let item = ClipboardItem(
                timestamp: Date(),
                firstCopiedAt: Date(),
                type: .image,
                textContent: imageURLs.map { $0.absoluteString }.joined(separator: "\n"),
                title: imageURLs.count > 1 ? "\(imageURLs.count) images" : "Image",
                fileURL: imageURLs.first,
                sizeLabel: "\(imageURLs.count) image\(imageURLs.count > 1 ? "s" : "")",
                appSource: sourceApp,
                appBundleID: sourceBundleID
            )
            Task { @MainActor in storage.addItem(item) }
            return
        }

        // 3. URLs / Links
        if types.contains(.URL),
           let urlStr = pasteboard.string(forType: .URL),
           !urlStr.isEmpty {
            let item = ClipboardItem(
                timestamp: Date(), firstCopiedAt: Date(), type: .link,
                textContent: urlStr, appSource: sourceApp, appBundleID: sourceBundleID
            )
            Task { @MainActor in storage.addItem(item) }
            return
        }

        // 4. Plain text (last)
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let item = ClipboardItem(
                timestamp: Date(), firstCopiedAt: Date(), type: .text,
                textContent: text, appSource: sourceApp, appBundleID: sourceBundleID
            )
            Task { @MainActor in storage.addItem(item) }
        }
    }

    // MARK: - Image helpers (no RAM retention)

    private func extractPNGFromTIFF(_ tiffData: Data?) -> Data? {
        guard let data = tiffData,
              let rep = NSBitmapImageRep(data: data) else { return nil }
        
        // Optimize image size if too large
        let optimized = optimizeImage(rep)
        return optimized.representation(using: .png, properties: [.compressionFactor: 0.8])
    }

    private func renderImageToPNG(_ image: NSImage) -> Data? {
        let rect = NSRect(origin: .zero, size: image.size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.current = ctx
        image.draw(in: rect)
        
        // Optimize and compress
        let optimized = optimizeImage(rep)
        return optimized.representation(using: .png, properties: [.compressionFactor: 0.8])
    }
    
    private func optimizeImage(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        let maxWidth: Int = 2000
        let maxHeight: Int = 2000
        let maxFileSize: Int = 5 * 1024 * 1024 // 5 MB
        
        var currentRep = rep
        let currentSize = rep.representation(using: .png, properties: [:])?.count ?? 0
        
        // Downscale if too large
        if rep.pixelsWide > maxWidth || rep.pixelsHigh > maxHeight || currentSize > maxFileSize {
            let scale = min(
                Double(maxWidth) / Double(rep.pixelsWide),
                Double(maxHeight) / Double(rep.pixelsHigh),
                1.0
            )
            
            let newWidth = Int(Double(rep.pixelsWide) * scale)
            let newHeight = Int(Double(rep.pixelsHigh) * scale)
            
            if let scaled = rep.representation(using: .png, properties: [:]),
               let scaledImage = NSImage(data: scaled) {
                scaledImage.size = NSSize(width: newWidth, height: newHeight)
                if let newRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                  pixelsWide: newWidth, pixelsHigh: newHeight,
                                                  bitsPerSample: 8, samplesPerPixel: 4,
                                                  hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .calibratedRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0),
                   let ctx = NSGraphicsContext(bitmapImageRep: newRep) {
                    NSGraphicsContext.current = ctx
                    scaledImage.draw(in: NSRect(origin: .zero, size: NSSize(width: newWidth, height: newHeight)))
                    NSGraphicsContext.restoreGraphicsState()
                    currentRep = newRep
                }
            }
        }
        
        return currentRep
    }

    private func savePNGToDisk(data: Data, source: String, bundleID: String?) {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/Images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let fileName = UUID().uuidString + ".png"
            let url = base.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            let item = ClipboardItem(
                timestamp: Date(), firstCopiedAt: Date(), type: .image,
                fileURL: url, sizeLabel: "\(data.count / 1024) KB",
                appSource: source, appBundleID: bundleID
            )
            Task { @MainActor in storage.addItem(item) }
        } catch { /* silently ignore write errors */ }
    }
    
    private func savePNGToDiskAndReturnURL(data: Data, source: String, bundleID: String?) -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/Images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let fileName = UUID().uuidString + ".png"
            let url = base.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch { 
            return nil
        }
    }

    // MARK: - Pasteboard write-back

    func copyToPasteboard(item: ClipboardItem, plainTextOnly: Bool) {
        stop()
        pasteboard.clearContents()

        switch item.type {
        case .text, .link:
            if let txt = item.textContent {
                pasteboard.setString(txt, forType: .string)
            }
        case .image:
            // Support multi-image record (URLs stored newline-separated in textContent)
            if let joined = item.textContent, item.title?.hasSuffix("images") == true {
                let imageURLs: [NSURL] = joined
                    .components(separatedBy: "\n")
                    .compactMap { URL(string: $0) as NSURL? }
                let images = imageURLs.compactMap { NSImage(contentsOf: $0 as URL) }
                pasteboard.writeObjects(images)
            } else if let url = item.fileURL, let img = NSImage(contentsOf: url) {
                pasteboard.writeObjects([img])
            }
        case .file:
            // Support multi-file record (URLs stored newline-separated in textContent)
            if let joined = item.textContent, item.title?.hasSuffix("files") == true {
                let urls: [NSURL] = joined
                    .components(separatedBy: "\n")
                    .compactMap { URL(string: $0) as NSURL? }
                pasteboard.writeObjects(urls)
            } else if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        default:
            break
        }

        lastChangeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.start()
        }
    }

    func triggerCmdV() {
        let vKeyCode: CGKeyCode = 0x09
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

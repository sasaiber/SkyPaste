import Foundation
import AppKit
import UniformTypeIdentifiers
import os
import UserNotifications

class ImagePasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .png {
            if let image = NSImage(contentsOf: url),
               let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                item.setData(pngData, forType: .png)
            }
        } else if type == .tiff {
            if let image = NSImage(contentsOf: url),
               let tiffData = image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
        } else if type == NSPasteboard.PasteboardType(rawValue: "public.jpeg") {
             if let image = NSImage(contentsOf: url),
               let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                item.setData(jpegData, forType: NSPasteboard.PasteboardType(rawValue: "public.jpeg"))
            }
        } else if type == .fileURL {
            if let data = url.absoluteString.data(using: .utf8) {
                item.setData(data, forType: .fileURL)
            }
        }
    }
}

class ClipboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var activeProviders: [Any] = []
    
    // Adaptive polling
    private var currentInterval: TimeInterval = 0.5
    private let minInterval: TimeInterval = 0.5
    private let maxInterval: TimeInterval = 2.0
    private var noChangeTicks: Int = 0

    let storage: Storage

    init(storage: Storage) {
        self.storage = storage
        self.lastChangeCount = pasteboard.changeCount
    }
    
    private func sendNotification(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: "enableNotifications") else { return }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            
            if let soundURL = Bundle.main.url(forResource: "clip", withExtension: "mp3") {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(soundURL.lastPathComponent))
            } else {
                content.sound = .default
            }
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
           
        }
    }

    func start() {
        scheduleTimer()
    }
    
    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: currentInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
                self?.scheduleTimer()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func checkForChanges() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else {
            noChangeTicks += 1
            if noChangeTicks > 10 {
                currentInterval = min(currentInterval + 0.5, maxInterval)
                noChangeTicks = 0
            }
            return
        }
        
        // Reset interval on change
        currentInterval = minInterval
        noChangeTicks = 0
        lastChangeCount = current
        processNewItem()
    }

    @MainActor
    private func processNewItem() {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let allItems = pasteboard.pasteboardItems ?? []
        let types = Set(pasteboard.types ?? [])

        // Collect string values immediately on main thread to avoid pasteboard sync issues
        let urlStr = types.contains(.URL) ? pasteboard.string(forType: .URL) : nil
        let plainTextStr = pasteboard.string(forType: .string)

        Task.detached {
            // 1. Multi-file / single-file: collect ALL file URLs from every pasteboard item
            var fileURLs: [URL] = []
            for pbItem in allItems {
                if let data = pbItem.data(forType: .fileURL),
                   let str = String(data: data, encoding: .utf8),
                   let url = URL(string: str) {
                    fileURLs.append(url)
                }
            }

            if !fileURLs.isEmpty {
                // Determine file type and metadata
                var exts = Set<String>()
                var totalSize: Int64 = 0
                for url in fileURLs {
                    exts.insert(url.pathExtension.lowercased())
                    if fileURLs.count < 1000 {
                        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let size = attr[.size] as? Int64 {
                            totalSize += size
                        }
                    }
                }
                
                var itemType: ItemType = .file
                let isImageOnly = exts.allSatisfy { ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "raw"].contains($0) }
                if isImageOnly && !exts.isEmpty {
                    itemType = .image
                }
                
                var item = ClipboardItem(
                    timestamp: Date(), 
                    firstCopiedAt: Date(), 
                    type: itemType,
                    textContent: fileURLs.map { $0.absoluteString }.joined(separator: "\n"),
                    title: fileURLs.count > 1 ? "\(fileURLs.count) files" : fileURLs.first?.lastPathComponent,
                    fileURL: fileURLs.first,
                    appSource: sourceApp, 
                    appBundleID: sourceBundleID,
                    extensions: Array(exts),
                    fileCount: fileURLs.count,
                    totalSizeBytes: totalSize,
                    thumbStatus: ThumbStatus.pending.rawValue
                )
                
                // Generate thumbs for up to 50 items if many
                let limit = fileURLs.count > 500 ? 50 : fileURLs.count
                for (index, url) in fileURLs.prefix(limit).enumerated() {
                    let (thumbURL, status) = await ThumbnailGenerator.shared.generateThumbnail(for: url)
                    if index == 0 {
                        item.thumbPath = thumbURL?.path
                        item.thumbStatus = status.rawValue
                    }
                }
                
                let finalItem = item
                await MainActor.run {
                    self.storage.addItem(finalItem)
                    self.sendNotification(title: "Copied", body: finalItem.title ?? "Clipboard Item")
                }
                return
            }

            // 2. Images — try MANY ways to extract ALL images (from data, not files)
            var imageURLs: [URL] = []
            
            // Method 1: Direct iteration through pasteboardItems
            for pbItem in allItems {
                autoreleasepool {
                    if let pngData = pbItem.data(forType: .png) {
                        if let url = self.savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                            imageURLs.append(url)
                        }
                    } else if let tiffData = pbItem.data(forType: .tiff) {
                        if let pngData = self.extractPNGFromTIFF(tiffData) {
                            if let url = self.savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                                imageURLs.append(url)
                            }
                        }
                    } else if let jpgData = pbItem.data(forType: NSPasteboard.PasteboardType(rawValue: "public.jpeg")) {
                        if let url = self.savePNGToDiskAndReturnURL(data: jpgData, source: sourceApp, bundleID: sourceBundleID) {
                            imageURLs.append(url)
                        }
                    }
                }
            }
            
            // Method 2: Try NSImage fallback if nothing found
            if imageURLs.isEmpty && (types.contains(.tiff) || types.contains(.png)) {
                let fallbackURL: URL? = await MainActor.run {
                    if NSImage.canInit(with: self.pasteboard),
                       let image = NSImage(pasteboard: self.pasteboard),
                       let data = self.renderImageToPNG(image) {
                        return self.savePNGToDiskAndReturnURL(data: data, source: sourceApp, bundleID: sourceBundleID)
                    }
                    return nil
                }
                if let url = fallbackURL {
                    imageURLs.append(url)
                }
            }
            
            if !imageURLs.isEmpty {
                var item = ClipboardItem(
                    timestamp: Date(), 
                    firstCopiedAt: Date(), 
                    type: .image,
                    textContent: imageURLs.map { $0.absoluteString }.joined(separator: "\n"),
                    title: imageURLs.count > 1 ? "\(imageURLs.count) images" : "Image",
                    fileURL: imageURLs.first,
                    sizeLabel: "\(imageURLs.count) image\(imageURLs.count > 1 ? "s" : "")",
                    appSource: sourceApp, 
                    appBundleID: sourceBundleID,
                    extensions: ["jpg"],
                    fileCount: imageURLs.count,
                    thumbStatus: ThumbStatus.pending.rawValue
                )
                
                for (index, url) in imageURLs.enumerated() {
                    let (thumbURL, status) = await ThumbnailGenerator.shared.generateThumbnail(for: url)
                    if index == 0 {
                        item.thumbPath = thumbURL?.path
                        item.thumbStatus = status.rawValue
                    }
                }
                
                let finalItem = item
                await MainActor.run {
                    self.storage.addItem(finalItem)
                    self.sendNotification(title: "Copied", body: finalItem.title ?? "Clipboard Item")
                }
                return
            }

            // 3. URLs / Links
            if let urlStr = urlStr, !urlStr.isEmpty {
                let item = ClipboardItem(
                    timestamp: Date(), firstCopiedAt: Date(), type: .link,
                    textContent: urlStr, title: urlStr,
                    appSource: sourceApp, appBundleID: sourceBundleID
                )
                let finalItem = item
                await MainActor.run {
                    self.storage.addItem(finalItem)
                    self.sendNotification(title: "Copied", body: finalItem.title ?? "Clipboard Item")
                }
                return
            }

            // 4. Plain text (last)
            if let text = plainTextStr, !text.isEmpty {
                let displayText = text.count > 100 ? String(text.prefix(100)) + "..." : text
                let item = ClipboardItem(
                    timestamp: Date(), firstCopiedAt: Date(), type: .text,
                    textContent: text, title: displayText,
                    appSource: sourceApp, appBundleID: sourceBundleID
                )
                let finalItem = item
                await MainActor.run {
                    self.storage.addItem(finalItem)
                    self.sendNotification(title: "Copied", body: finalItem.title ?? "Clipboard Item")
                }
            }
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

    private func savePNGToDiskAndReturnURL(data: Data, source: String, bundleID: String?) -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/Images", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            
            guard let image = NSImage(data: data) else { return nil }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            
            let maxSize: Int = 2_000_000
            var finalData: Data = data
            var ext = "png"
            
            if data.count > maxSize {
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    finalData = jpegData
                    ext = "jpg"
                }
            } else {
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    finalData = pngData
                }
            }
            
            let fileName = UUID().uuidString + "." + ext
            let url = base.appendingPathComponent(fileName)
            try finalData.write(to: url, options: .atomic)
            return url
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }
    
    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp", "heic"]
        let pathExtension = url.pathExtension.lowercased()
        return imageExtensions.contains(pathExtension)
    }

    // MARK: - Pasteboard write-back

    func copyToPasteboard(item: ClipboardItem, plainTextOnly: Bool) {
        stop()
        pasteboard.clearContents()

        if plainTextOnly {
            if let txt = item.textContent {
                pasteboard.setString(txt, forType: .string)
            }
            lastChangeCount = pasteboard.changeCount
            sendNotification(title: "Pasted from SkyPaste", body: item.title ?? "Plain Text")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.start()
            }
            return
        }

        switch item.type {
        case .text, .link:
            if let txt = item.textContent {
                pasteboard.setString(txt, forType: .string)
            }
        case .image:
            if let joined = item.textContent {
                let imageURLs: [URL] = joined
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .compactMap { urlString -> URL? in
                        if let url = URL(string: urlString) {
                            if url.scheme == "file" { return url }
                        }
                        return URL(fileURLWithPath: urlString)
                    }
                let images = imageURLs.compactMap { NSImage(contentsOf: $0) }
                if !images.isEmpty {
                    pasteboard.writeObjects(images)
                }
            } else if let url = item.fileURL, let img = NSImage(contentsOf: url) {
                pasteboard.writeObjects([img])
            }
        case .file:
            if let joined = item.textContent {
                let urls: [URL] = joined
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .compactMap { urlString -> URL? in
                        if let url = URL(string: urlString) {
                            if url.scheme == "file" { return url }
                        }
                        return URL(fileURLWithPath: urlString)
                    }
                pasteboard.writeObjects(urls as [NSURL])
            } else if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        default:
            break
        }

        lastChangeCount = pasteboard.changeCount
        sendNotification(title: "Pasted from SkyPaste", body: item.title ?? "Clipboard Item")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.start()
        }
    }

    func triggerCmdV() {
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Add flag that left/right modifier key has been pressed (like Maccy does)
        let cmdFlag = CGEventFlags(rawValue: UInt64(CGEventFlags.maskCommand.rawValue) | 0x000008)

        // Disable local keyboard events while pasting
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = cmdFlag
        keyUp?.flags = cmdFlag

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}

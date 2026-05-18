import Foundation
import AppKit
import UniformTypeIdentifiers
import os
import UserNotifications

class ClipboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

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
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
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
            // Check if ALL files are images - if so, treat as images not files!
            let imageFiles = fileURLs.filter { isImageFile($0) }
            if imageFiles.count == fileURLs.count && !imageFiles.isEmpty {
                var imageURLs: [URL] = []
                for imgURL in imageFiles {
                    guard let image = NSImage(contentsOf: imgURL) else { continue }
                    
                    // Save as PNG
                    if let data = renderImageToPNG(image) {
                        if let url = savePNGToDiskAndReturnURL(data: data, source: sourceApp, bundleID: sourceBundleID) {
                            imageURLs.append(url)
                        }
                    }
                }
                
            if !imageURLs.isEmpty {
                let urls = imageURLs
                Task.detached {
                    let item = ClipboardItem(
                        timestamp: Date(),
                        firstCopiedAt: Date(),
                        type: .image,
                        textContent: urls.map { $0.absoluteString }.joined(separator: "\n"),
                        title: urls.count > 1 ? "\(urls.count) images" : "Image",
                        fileURL: urls.first,
                        sizeLabel: "\(urls.count) image\(urls.count > 1 ? "s" : "")",
                        appSource: sourceApp,
                        appBundleID: sourceBundleID
                    )
                    await MainActor.run {
                        self.storage.addItem(item)
                        self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
                    }
                }
                return
            }
            }
            
            // Not all images, treat as regular files
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
            Task { @MainActor in
                storage.addItem(item)
                self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
            }
            return
        }

        // 2. Images — try MANY ways to extract ALL images
        var imageURLs: [URL] = []
        
        // Method 1: Direct iteration through pasteboardItems
        for pbItem in allItems {
            if let pngData = pbItem.data(forType: .png) {
                if let url = savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                    imageURLs.append(url)
                }
            } else if let tiffData = pbItem.data(forType: .tiff) {
                if let pngData = extractPNGFromTIFF(tiffData) {
                    if let url = savePNGToDiskAndReturnURL(data: pngData, source: sourceApp, bundleID: sourceBundleID) {
                        imageURLs.append(url)
                    }
                }
            } else if let jpgData = pbItem.data(forType: NSPasteboard.PasteboardType(rawValue: "public.jpeg")) {
                if let url = savePNGToDiskAndReturnURL(data: jpgData, source: sourceApp, bundleID: sourceBundleID) {
                    imageURLs.append(url)
                }
            }
        }
        
        // Method 2: Try NSImage fallback if nothing found
        if imageURLs.isEmpty && (types.contains(.tiff) || types.contains(.png)),
           NSImage.canInit(with: pasteboard),
           let image = NSImage(pasteboard: pasteboard),
           let data = renderImageToPNG(image) {
            if let url = savePNGToDiskAndReturnURL(data: data, source: sourceApp, bundleID: sourceBundleID) {
                imageURLs.append(url)
            }
        }
        
            if !imageURLs.isEmpty {
                let urls = imageURLs
                Task.detached {
                    let item = ClipboardItem(
                        timestamp: Date(), 
                        firstCopiedAt: Date(), 
                        type: .image,
                        textContent: urls.map { $0.absoluteString }.joined(separator: "\n"),
                        title: urls.count > 1 ? "\(urls.count) images" : "Image",
                        fileURL: urls.first,
                        sizeLabel: "\(urls.count) image\(urls.count > 1 ? "s" : "")",
                        appSource: sourceApp, 
                        appBundleID: sourceBundleID
                    )
                    await MainActor.run {
                        self.storage.addItem(item)
                        self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
                    }
                }
                return
            }

        // 3. URLs / Links
        if types.contains(.URL),
           let urlStr = pasteboard.string(forType: .URL),
           !urlStr.isEmpty {
            let item = ClipboardItem(
                timestamp: Date(), firstCopiedAt: Date(), type: .link,
                textContent: urlStr, title: urlStr,
                appSource: sourceApp, appBundleID: sourceBundleID
            )
            Task { @MainActor in
                storage.addItem(item)
                self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
            }
            return
        }

        // 4. Plain text (last)
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let displayText = text.count > 100 ? String(text.prefix(100)) + "..." : text
            let item = ClipboardItem(
                timestamp: Date(), firstCopiedAt: Date(), type: .text,
                textContent: text, title: displayText,
                appSource: sourceApp, appBundleID: sourceBundleID
            )
            Task { @MainActor in
                storage.addItem(item)
                self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
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
            
            if data.count > maxSize {
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    finalData = jpegData
                }
            } else {
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    finalData = pngData
                }
            }
            
            let ext = finalData.count > maxSize ? "jpg" : "png"
            let fileName = UUID().uuidString + "." + ext
            let url = base.appendingPathComponent(fileName)
            try finalData.write(to: url, options: .atomic)
            return url
        } catch {
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

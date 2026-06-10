import Foundation
import AppKit
import UniformTypeIdentifiers
import os
import UserNotifications

private class ImagePasteboardProvider: NSObject, NSPasteboardItemDataProvider {
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
    private var activeProviders: [ImagePasteboardProvider] = []
    private var processingTask: Task<Void, Never>?
    private var processingGeneration: UInt64 = 0
    
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

    @MainActor
    private func handleCopyFeedback(for item: ClipboardItem) {
        self.storage.addItem(item)
        if UserDefaults.standard.bool(forKey: "bounceIconOnCopy") {
            AppDelegate.shared.bounceStatusItem()
        }
        self.sendNotification(title: "Copied", body: item.title ?? "Clipboard Item")
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
        processingTask?.cancel()
        processingTask = nil
        activeProviders.removeAll()
    }

    private func restartMonitoringAfterPaste() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.activeProviders.removeAll()
            self?.start()
        }
    }

    private func shouldContinueProcessing(generation: UInt64) async -> Bool {
        if Task.isCancelled { return false }
        return await MainActor.run { self.processingGeneration == generation }
    }

    private func previewLimit(for itemCount: Int) -> Int {
        let unlimitedMediaPreviews = UserDefaults.standard.bool(forKey: "unlimitedMediaPreviews")
        let maxLimit = UserDefaults.standard.integer(forKey: "maxPreviewsLimit")
        let resolvedMax = maxLimit == 0 ? 10 : maxLimit
        return unlimitedMediaPreviews ? itemCount : min(itemCount, resolvedMax)
    }

    private func warmUpThumbnails(urls: [URL], skipFirst: Bool) {
        let warmURLs = skipFirst ? Array(urls.dropFirst()) : urls
        guard !warmURLs.isEmpty else { return }

        Task.detached(priority: .background) {
            for url in warmURLs {
                if Task.isCancelled { return }
                _ = await ThumbnailGenerator.shared.generateThumbnail(for: url)
            }
        }
    }

    private func extractURLs(from joined: String) -> [URL] {
        joined
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { urlString -> URL? in
                if let url = URL(string: urlString), url.scheme == "file" {
                    return url
                }
                return URL(fileURLWithPath: urlString)
            }
    }

    private func writeImageURLsToPasteboard(_ urls: [URL]) {
        let jpegType = NSPasteboard.PasteboardType(rawValue: "public.jpeg")
        let providers = urls.map(ImagePasteboardProvider.init)
        activeProviders = providers

        let items: [NSPasteboardItem] = providers.map { provider in
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.png, .tiff, jpegType, .fileURL])
            return item
        }

        pasteboard.writeObjects(items)
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
        let allItems = pasteboard.pasteboardItems ?? []
        let pbTypes = pasteboard.types ?? []
        let typeStrings = Set(pbTypes.map { $0.rawValue })
        
        var sourceApp = "Unknown"
        var sourceBundleID: String? = nil
        var remoteDeviceName: String? = nil
        let isRemote = typeStrings.contains("com.apple.is-remote-clipboard") || typeStrings.contains("com.apple.is-remote-pasteboard")
        
        if isRemote {
            let syncEnabled = UserDefaults.standard.object(forKey: "syncEnabled") as? Bool ?? true
            if !syncEnabled {
                return
            }
            if let remoteSourceID = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) {
                sourceBundleID = remoteSourceID
                let shortName = remoteSourceID.components(separatedBy: ".").last?.capitalized ?? "App"
                sourceApp = shortName
                remoteDeviceName = "Remote (\(shortName))"
            } else {
                remoteDeviceName = "Handoff Device"
            }
        } else {
            sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }

        if let bundleID = sourceBundleID,
           let ignoredAppsData = UserDefaults.standard.data(forKey: "ignoredAppBundleIDs"),
           let ignoredApps = try? JSONDecoder().decode([String].self, from: ignoredAppsData),
           ignoredApps.contains(bundleID) {
            // App is ignored, skip
            return
        }

        // Collect string values immediately on main thread to avoid pasteboard sync issues
        let urlStr = pbTypes.contains(.URL) ? pasteboard.string(forType: .URL) : nil
        let plainTextStr = pasteboard.string(forType: .string)

        processingTask?.cancel()
        processingGeneration &+= 1
        let generation = processingGeneration

        processingTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard await self.shouldContinueProcessing(generation: generation) else { return }

            // 1. Multi-file / single-file: collect ALL file URLs from every pasteboard item
            var fileURLs: [URL] = []
            for pbItem in allItems {
                if await !self.shouldContinueProcessing(generation: generation) { return }
                if let data = pbItem.data(forType: .fileURL),
                   let str = String(data: data, encoding: .utf8),
                   let url = URL(string: str), url.isFileURL {
                    fileURLs.append(url)
                }
            }

            // Workaround for browsers copying images as temporary file URLs
            let hasImageData = pbTypes.contains(.png) || pbTypes.contains(.tiff) || pbTypes.contains(NSPasteboard.PasteboardType(rawValue: "public.jpeg"))
            if fileURLs.count == 1 && hasImageData {
                if let url = fileURLs.first, (url.path.contains("/var/folders/") || url.path.contains("/tmp/") || url.path.contains("/Caches/")) {
                    var isTempImage = false
                    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                        isTempImage = type.conforms(to: .image)
                    } else if ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff"].contains(url.pathExtension.lowercased()) {
                        isTempImage = true
                    } else if let _ = NSImage(contentsOf: url) {
                        isTempImage = true
                    }
                    
                    if isTempImage {
                        fileURLs.removeAll() // Let Section 2 extract the actual image data from pasteboard
                    }
                }
            }

            if !fileURLs.isEmpty {
                var exts = Set<String>()
                var totalSize: Int64 = 0
                for url in fileURLs {
                    if await !self.shouldContinueProcessing(generation: generation) { return }
                    exts.insert(url.pathExtension.lowercased())
                    if fileURLs.count < 1000,
                       let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attr[.size] as? Int64 {
                        totalSize += size
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
                    remoteDeviceName: remoteDeviceName,
                    appSource: sourceApp,
                    appBundleID: sourceBundleID,
                    extensions: Array(exts),
                    fileCount: fileURLs.count,
                    totalSizeBytes: totalSize,
                    thumbStatus: ThumbStatus.pending.rawValue
                )

                let disableMediaPreviews = UserDefaults.standard.bool(forKey: "disableMediaPreviews")
                if !disableMediaPreviews,
                   let firstURL = fileURLs.first {
                    let (thumbURL, status) = await ThumbnailGenerator.shared.generateThumbnail(for: firstURL)
                    guard await self.shouldContinueProcessing(generation: generation) else { return }
                    item.thumbPath = thumbURL?.path
                    item.thumbStatus = status.rawValue

                    let warmLimit = fileURLs.count > 500 ? 50 : fileURLs.count
                    if warmLimit > 1 {
                        self.warmUpThumbnails(urls: Array(fileURLs.prefix(warmLimit)), skipFirst: true)
                    }
                }

                let finalItem = item
                guard await self.shouldContinueProcessing(generation: generation) else { return }
                await MainActor.run {
                    guard self.processingGeneration == generation else { return }
                    self.handleCopyFeedback(for: finalItem)
                }
                return
            }

            // 2. Images — try MANY ways to extract ALL images (from data, not files)
            var imageURLs: [URL] = []

            for pbItem in allItems {
                if await !self.shouldContinueProcessing(generation: generation) { return }
                autoreleasepool {
                    if let pngData = pbItem.data(forType: .png) {
                            if let url = self.savePNGToDiskAndReturnURL(data: pngData) {

                            imageURLs.append(url)
                        }
                    } else if let tiffData = pbItem.data(forType: .tiff) {
                        if let pngData = self.extractPNGFromTIFF(tiffData) {
                        if let url = self.savePNGToDiskAndReturnURL(data: pngData) {

                                imageURLs.append(url)
                            }
                        }
                    } else if let jpgData = pbItem.data(forType: NSPasteboard.PasteboardType(rawValue: "public.jpeg")) {
                        if let url = self.savePNGToDiskAndReturnURL(data: jpgData) {
                            imageURLs.append(url)
                        }
                    }
                }
            }

            if imageURLs.isEmpty && (pbTypes.contains(.tiff) || pbTypes.contains(.png)) {
                let fallbackURL: URL? = await MainActor.run {
                    if NSImage.canInit(with: self.pasteboard),
                       let image = NSImage(pasteboard: self.pasteboard),
                       let data = self.renderImageToPNG(image) {
                        return self.savePNGToDiskAndReturnURL(data: data)
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
                    remoteDeviceName: remoteDeviceName,
                    sizeLabel: "\(imageURLs.count) image\(imageURLs.count > 1 ? "s" : "")",
                    appSource: sourceApp,
                    appBundleID: sourceBundleID,
                    extensions: ["jpg"],
                    fileCount: imageURLs.count,
                    thumbStatus: ThumbStatus.pending.rawValue
                )

                let disableMediaPreviews = UserDefaults.standard.bool(forKey: "disableMediaPreviews")
                if !disableMediaPreviews,
                   let firstURL = imageURLs.first {
                    let (thumbURL, status) = await ThumbnailGenerator.shared.generateThumbnail(for: firstURL)
                    guard await self.shouldContinueProcessing(generation: generation) else { return }
                    item.thumbPath = thumbURL?.path
                    item.thumbStatus = status.rawValue

                    let limit = self.previewLimit(for: imageURLs.count)
                    if limit > 1 {
                        self.warmUpThumbnails(urls: Array(imageURLs.prefix(limit)), skipFirst: true)
                    }
                }

                let finalItem = item
                guard await self.shouldContinueProcessing(generation: generation) else { return }
                await MainActor.run {
                    guard self.processingGeneration == generation else { return }
                    self.handleCopyFeedback(for: finalItem)
                }
                return
            }

            // 3. URLs / Links
            var detectedURL = urlStr
            if (detectedURL == nil || detectedURL!.isEmpty), let text = plainTextStr {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    detectedURL = trimmed
                }
            }
            
            if let linkStr = detectedURL, !linkStr.isEmpty {
                let item = ClipboardItem(
                    timestamp: Date(), firstCopiedAt: Date(), type: .link,
                    textContent: linkStr, title: linkStr,
                    remoteDeviceName: remoteDeviceName,
                    appSource: sourceApp, appBundleID: sourceBundleID
                )
                guard await self.shouldContinueProcessing(generation: generation) else { return }
                await MainActor.run {
                    guard self.processingGeneration == generation else { return }
                    self.handleCopyFeedback(for: item)
                }
                return
            }

            // 4. Plain text (last)
            if let text = plainTextStr, !text.isEmpty {
                let displayText = text.count > 100 ? String(text.prefix(100)) + "..." : text
                let item = ClipboardItem(
                    timestamp: Date(), firstCopiedAt: Date(), type: .text,
                    textContent: text, title: displayText,
                    remoteDeviceName: remoteDeviceName,
                    appSource: sourceApp, appBundleID: sourceBundleID
                )
                guard await self.shouldContinueProcessing(generation: generation) else { return }
                await MainActor.run {
                    guard self.processingGeneration == generation else { return }
                    self.handleCopyFeedback(for: item)
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

    private func savePNGToDiskAndReturnURL(data: Data) -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/Images", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            
            let maxSize: Int = 2_000_000
            var finalData: Data = data
            var ext = "png"

            if data.count > maxSize {
                guard let image = NSImage(data: data),
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    return nil
                }
                finalData = jpegData
                ext = "jpg"
            }
            
            let fileName = UUID().uuidString + "." + ext
            let url = base.appendingPathComponent(fileName)
            try finalData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
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
            restartMonitoringAfterPaste()
            return
        }

        switch item.type {
        case .text, .link:
            if let txt = item.textContent {
                pasteboard.setString(txt, forType: .string)
            }
        case .image:
            if let joined = item.textContent {
                let imageURLs = extractURLs(from: joined)
                if !imageURLs.isEmpty {
                    writeImageURLsToPasteboard(imageURLs)
                }
            } else if let url = item.fileURL {
                writeImageURLsToPasteboard([url])
            }
        case .file:
            if let joined = item.textContent {
                let urls = extractURLs(from: joined)
                pasteboard.writeObjects(urls as [NSURL])
                let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
                pasteboard.addTypes([legacyType], owner: nil)
                let paths = urls.map { $0.path }
                pasteboard.setPropertyList(paths, forType: legacyType)
            } else if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
                let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
                pasteboard.addTypes([legacyType], owner: nil)
                pasteboard.setPropertyList([url.path], forType: legacyType)
            }
        default:
            break
        }

        lastChangeCount = pasteboard.changeCount
        sendNotification(title: "Pasted from SkyPaste", body: item.title ?? "Clipboard Item")
        restartMonitoringAfterPaste()
    }

    @MainActor
    func copyURLsToPasteboard(urls: [URL]) {
        stop()
        pasteboard.clearContents()
        
        // Write modern NSURL objects
        pasteboard.writeObjects(urls as [NSURL])
        
        // Explicitly add and write legacy filenames plist array for Finder compatibility
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pasteboard.addTypes([legacyType], owner: nil)
        let paths = urls.map { $0.path }
        pasteboard.setPropertyList(paths, forType: legacyType)
        
        lastChangeCount = pasteboard.changeCount
        
        // Restart polling after delay using Swift concurrency (MainActor)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { self?.start() }
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

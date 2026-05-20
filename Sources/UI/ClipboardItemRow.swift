import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    @ObservedObject var storage: Storage
    let item: ClipboardItem
    let folders: [AppFolder]
    let hoveredItemID: UUID?
    var selectedFolderID: UUID? = nil   // current view context
    var isHovered: Bool { hoveredItemID == item.id }
    
    var onPin: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onAssignToFolder: ((UUID?) -> Void)? = nil
    var onImageTap: ((URL) -> Void)? = nil
    var onExtractFile: (([URL], Bool, UUID?) -> Void)? = nil
    var onCreateFolder: (([URL]?) -> Void)? = nil
    var onDeleteFiles: (([URL]) -> Void)? = nil
    
    @State private var showFullText: Bool = false
    @State private var isPopoverHovered: Bool = false
    @State private var hideTask: DispatchWorkItem? = nil
    @State private var loadedThumbnails: [URL: NSImage] = [:]
    
    @State private var selectedURLs: Set<URL> = []
    @State private var innerHoveredURL: URL? = nil
    @State private var isSystemMenuOpen = false
    
    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFinderKey") private var hkFinderKey: String = "f"
    @AppStorage("hkFinderModifiers") private var hkFinderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    @AppStorage("previewDelay") private var previewDelay: Double = 200
    @AppStorage("showSpecialSymbols") private var showSpecialSymbols: Bool = true
    @AppStorage("disableMediaPreviews") private var disableMediaPreviews: Bool = false
    @AppStorage("unlimitedMediaPreviews") private var unlimitedMediaPreviews: Bool = true
    @AppStorage("maxPreviewsLimit") private var maxPreviewsLimit: Int = 10
    

    
    private func formatShortcut(key: String, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var str = ""
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }
        return str + key.uppercased()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 1. App Icon
            if let icon = getAppIcon(bundleID: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                iconForType(item.type)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
            }
            
            // 2. Main Content
            VStack(alignment: .leading, spacing: 2) {
                if item.type == .image || item.type == .file {
                    let urls = extractURLs(from: item)
                    if let title = item.title {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundColor(.accentColor)
                    }
                    
                    if urls.count == 1 {
                        Text(urls[0].path)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                            .truncationMode(.middle)
                    } else if !urls.isEmpty {
                        Text(urls.map { $0.lastPathComponent }.joined(separator: ", "))
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                            .truncationMode(.tail)
                    }
                    
                    // Render Thumbnails
                    if !urls.isEmpty {
                        renderThumbnails(urls: urls, count: item.fileCount ?? urls.count)
                    }
                } else {
                    let text = item.textContent ?? "Empty"
                    let displayText = showSpecialSymbols ? replaceSpecialSymbols(text) : text
                    Text(displayText)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
            
            Spacer(minLength: 0)
            
            // 3. Trailing: persistent pin + hover actions + time
            HStack(spacing: 6) {
                // Pin — always shown if pinned, shown on hover otherwise
                Button(action: { onPin?() }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(item.isPinned ? .accentColor : .secondary)
                .opacity(item.isPinned || isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                
                if isHovered {
                    Menu {
                        ForEach(folders) { folder in
                            Button("\(folder.displayEmoji) \(folder.name)") {
                                onAssignToFolder?(folder.id)
                            }
                        }
                        if item.folderID != nil {
                            Divider()
                            Button("Remove from Folder") {
                                onAssignToFolder?(nil)
                            }
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundColor(.secondary)
                    
                    // Only show delete if item isn't in a folder, or we're inside that folder
                    if item.folderID == nil || selectedFolderID == item.folderID {
                        Button(action: { onDelete?() }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                } else {
                    Text(timeAgoDisplay(date: item.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : (item.isPinned ? Color.accentColor.opacity(0.05) : Color.clear))
        )
        // Edge Popover for metadata & full text
        .popover(isPresented: $showFullText, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            popoverContent(for: item)
                .onHover { popoverHovered in
                    self.isPopoverHovered = popoverHovered
                    if popoverHovered {
                        storage.hoveredItemID = item.id
                    } else if !self.isHovered && !isSystemMenuOpen {
                        self.showFullText = false
                    }
                }
                .onDisappear {
                    selectedURLs.removeAll()
                    innerHoveredURL = nil
                    storage.popoverSelectedURLs.removeAll()
                    storage.popoverHoveredURL = nil
                }
        }
        .onChange(of: showFullText) { _, isShown in
            if !isShown {
                selectedURLs.removeAll()
                innerHoveredURL = nil
                storage.popoverSelectedURLs.removeAll()
                storage.popoverHoveredURL = nil
            }
        }
        .onChange(of: hoveredItemID) { _, newHoveredID in
            hideTask?.cancel()
            let shouldShowPopover = true
            
            if newHoveredID == item.id {
                if shouldShowPopover {
                    let delaySeconds = max(0, previewDelay / 1000.0)
                    if delaySeconds < 0.01 {
                        self.showFullText = true
                    } else {
                        let task = DispatchWorkItem { self.showFullText = true }
                        self.hideTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: task)
                    }
                }
            } else {
                // Mouse left THIS item
                if newHoveredID != nil {
                    // Mouse entered ANOTHER item - immediately close this popover to prevent overlap bug
                    self.showFullText = false
                    self.isPopoverHovered = false
                } else {
                    // Mouse left entirely, use the timer gap for the popover bridge
                    let task = DispatchWorkItem {
                        if !self.isPopoverHovered && !self.isSystemMenuOpen {
                            self.showFullText = false
                        }
                    }
                    self.hideTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isSystemMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isSystemMenuOpen = false
        }
    }
    
    // Extracted Popover view
    @ViewBuilder
    private func popoverContent(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                if let icon = getAppIcon(bundleID: item.appBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading) {
                    Text(item.appSource ?? "Unknown")
                        .font(.headline)
                    Text("\(formatFullDate(item.timestamp))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let count = item.copyCount, count > 1 {
                    Text("Copied: \(count)")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Hover shortcuts hints
            HStack(spacing: 12) {
                Text("\(formatShortcut(key: hkPinKey, modifiers: hkPinModifiers)) to \(item.isPinned ? "Unpin" : "Pin")")
                Text("\(formatShortcut(key: hkDeleteKey, modifiers: hkDeleteModifiers)) to Delete")
                Text("\(formatShortcut(key: hkFinderKey, modifiers: hkFinderModifiers)) to View in Finder")
                Text("Click to Paste")
                Text("⌥+Click to Paste Plain")
                Text("⇧+Click to Toggle Select")
                Text("⌘+Click to Select Single")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 2)
            
            Divider()
            
            // Content
            if item.type == .image || item.type == .file {
                let urls = extractURLs(from: item)
                
                if !urls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = item.title {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal)
                        }
                        Divider()
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                    HStack(spacing: 12) {
                                        Image(nsImage: getPreviewIcon(for: url, at: index))
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .cornerRadius(6)
                                            .clipped()
                                            .overlay(
                                                Group {
                                                    if let icon = getAppIcon(bundleID: item.appBundleID) {
                                                        Image(nsImage: icon)
                                                            .resizable()
                                                            .frame(width: 12, height: 12)
                                                            .background(Color.white)
                                                            .clipShape(Circle())
                                                            .padding(2)
                                                    }
                                                }, alignment: .bottomTrailing
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .lineLimit(1)
                                            
                                             Text(url.path)
                                                 .font(.system(size: 10, design: .monospaced))
                                                 .foregroundColor(.secondary)
                                                 .truncationMode(.middle)
                                                 .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        selectedURLs.contains(url) ? Color.accentColor.opacity(0.15) :
                                        (innerHoveredURL == url ? Color.secondary.opacity(0.1) : Color.clear)
                                    )
                                    .cornerRadius(8)
                                     .contentShape(Rectangle())
                                     .onCopyCommand {
                                         copyFileToPasteboard([url])
                                         let provider = NSItemProvider(object: url as NSURL)
                                         return [provider]
                                     }
                                     .onHover { h in
                                        if h { 
                                            innerHoveredURL = url 
                                            storage.popoverHoveredURL = url
                                            if NSEvent.modifierFlags.contains(.shift) {
                                                if selectedURLs.contains(url) { selectedURLs.remove(url) }
                                                else { selectedURLs.insert(url) }
                                                storage.popoverSelectedURLs = Array(selectedURLs)
                                            }
                                        }
                                        else if innerHoveredURL == url { 
                                            innerHoveredURL = nil 
                                            if storage.popoverHoveredURL == url { storage.popoverHoveredURL = nil }
                                        }
                                    }
                                     .onTapGesture {
                                         let flags = NSEvent.modifierFlags
                                         if flags.contains(.command) {
                                             // ⌘+Click: Select ONLY this one file (single selection)
                                             selectedURLs = [url]
                                             storage.popoverSelectedURLs = [url]
                                         } else if flags.contains(.shift) {
                                            // ⇧+Click: Toggle Select
                                            if selectedURLs.contains(url) { selectedURLs.remove(url) }
                                            else { selectedURLs.insert(url) }
                                            storage.popoverSelectedURLs = Array(selectedURLs)
                                        } else {
                                            // Normal Click: Copy and Paste (or just copy if auto-paste is disabled)
                                            selectedURLs = [url]
                                            storage.popoverSelectedURLs = Array(selectedURLs)
                                            
                                             // Copy file URL to pasteboard
                                             copyFileToPasteboard([url])
                                            
                                            // Auto-paste if active
                                            if UserDefaults.standard.bool(forKey: "autoPasteActive") {
                                                AppDelegate.shared.monitorRef?.triggerCmdV()
                                                WindowManager.shared.close()
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        let isMulti = selectedURLs.count > 1
                                        let urlsToActOn = selectedURLs.isEmpty ? [url] : (selectedURLs.contains(url) ? Array(selectedURLs) : [url])
                                        let isFullSelection = urlsToActOn.count == urls.count
                                        
                                         Button(action: {
                                             copyFileToPasteboard(urlsToActOn)
                                         }) {
                                            Text(isMulti ? "Copy \(urlsToActOn.count) Files" : "Copy File")
                                            Image(systemName: "doc.on.clipboard")
                                        }
                                        
                                        Divider()
                                        
                                        Button(action: { 
                                            if isFullSelection {
                                                onPin?()
                                            } else {
                                                onExtractFile?(urlsToActOn, true, item.folderID) 
                                            }
                                        }) {
                                            Text(isMulti ? "Pin Selected Files" : "Pin File")
                                            Image(systemName: "pin")
                                        }
                                        
                                        Menu("Add to Folder") {
                                            Button(action: { 
                                                if isFullSelection {
                                                    onCreateFolder?(nil)
                                                } else {
                                                    onCreateFolder?(urlsToActOn) 
                                                }
                                            }) {
                                                Text("Create New Folder...")
                                                Image(systemName: "folder.badge.plus")
                                            }
                                            Divider()
                                            ForEach(folders) { folder in
                                                Button(action: { 
                                                    if isFullSelection {
                                                        onAssignToFolder?(folder.id)
                                                    } else {
                                                        onExtractFile?(urlsToActOn, false, folder.id) 
                                                    }
                                                }) {
                                                    Text("\(folder.displayEmoji) \(folder.name)")
                                                }
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        Button(action: {
                                            for u in urlsToActOn {
                                                NSWorkspace.shared.activateFileViewerSelecting([u])
                                            }
                                        }) {
                                            Text(isMulti ? "Show in Finder (\(urlsToActOn.count))" : "Show in Finder")
                                            Image(systemName: "magnifyingglass")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive, action: {
                                            if isFullSelection {
                                                onDelete?()
                                            } else {
                                                onDeleteFiles?(urlsToActOn)
                                            }
                                        }) {
                                            Text(isMulti ? "Delete Selected Files" : "Delete File")
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .onDrag {
                                        let urlsToDrag = selectedURLs.isEmpty ? [url] : (selectedURLs.contains(url) ? Array(selectedURLs) : [url])
                                        let provider = NSItemProvider(object: urlsToDrag.first! as NSURL)
                                        return provider
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                        }
                         .frame(maxHeight: 400)
                    }
                    
                    // Hidden handler for system Cmd+C in preview popover (SwiftUI keyboardShortcut pattern)
                    Button {
                        let target: [URL] = selectedURLs.isEmpty ? (innerHoveredURL != nil ? [innerHoveredURL!] : []) : Array(selectedURLs)
                        if !target.isEmpty { copyFileToPasteboard(target) }
                    } label: {
                        EmptyView()
                    }
                    .keyboardShortcut(KeyEquivalent("c"), modifiers: [.command])
                    .hidden()
                }
            } else {
                ScrollView {
                    Text(item.textContent ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                }
            }
        }
        .frame(width: 450, height: (item.type == .file || item.type == .image) ? nil : 500)
    }
    
    // Helpers
    private func copyFileToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pb.addTypes([legacy], owner: nil)
        pb.setPropertyList(urls.map { $0.path }, forType: legacy)
    }
    
    private func isImageURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"].contains(ext)
    }
    
    @ViewBuilder
    private func iconForType(_ type: ItemType) -> some View {
        switch type {
        case .text: Image(systemName: "doc.text.fill")
        case .link: Image(systemName: "link.circle.fill")
        case .image: Image(systemName: "photo.fill")
        case .file: Image(systemName: "doc.fill")
        case .other: Image(systemName: "doc.on.clipboard.fill")
        }
    }
    
    private func timeAgoDisplay(date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
    
    private func replaceSpecialSymbols(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "⏎ ")
            .replacingOccurrences(of: "\t", with: "⇥ ")
            .replacingOccurrences(of: "\r", with: "↵ ")
    }
    
    private func getAppIcon(bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
    
    private func extractURLs(from item: ClipboardItem) -> [URL] {
        if let content = item.textContent {
            return content.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .compactMap { urlString -> URL? in
                    if let url = URL(string: urlString) {
                        if url.scheme == "file" {
                            return url
                        }
                    }
                    return URL(fileURLWithPath: urlString)
                }
        } else if let url = item.fileURL {
            return [url]
        }
        return []
    }
    
    private func getIcon(for url: URL) -> NSImage {
        if !disableMediaPreviews,
           let thumbURL = ThumbnailGenerator.shared.getExistingThumbnailURL(for: url),
           let img = NSImage(contentsOf: thumbURL) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    /// Returns a rich thumbnail for items within the preview limit, plain file icon for the rest.
    private func getPreviewIcon(for url: URL, at index: Int) -> NSImage {
        if disableMediaPreviews {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let limit = unlimitedMediaPreviews ? Int.max : max(0, maxPreviewsLimit)
        if index < limit,
           let thumbURL = ThumbnailGenerator.shared.getExistingThumbnailURL(for: url),
           let img = NSImage(contentsOf: thumbURL) {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    @ViewBuilder
    private func renderThumbnails(urls: [URL], count: Int) -> some View {
        if disableMediaPreviews {
            EmptyView()
        } else if count == 1, let first = urls.first {
            Image(nsImage: getIcon(for: first))
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .cornerRadius(6)
                .clipped()
        } else if count >= 2 && count <= 9 {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 2), count: min(3, count)), spacing: 2) {
                ForEach(urls.prefix(count), id: \.self) { url in
                    Image(nsImage: getIcon(for: url))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                        .clipped()
                }
            }
        } else if count >= 10 && count <= 99 {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 2), count: 3), spacing: 2) {
                ForEach(urls.prefix(9), id: \.self) { url in
                    Image(nsImage: getIcon(for: url))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .cornerRadius(2)
                        .clipped()
                }
            }
            .overlay(
                Text("+\(count - 9)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .offset(x: 10, y: 10)
            )
        } else if count >= 100 {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 2), count: 2), spacing: 2) {
                ForEach(urls.prefix(4), id: \.self) { url in
                    Image(nsImage: getIcon(for: url))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .cornerRadius(2)
                        .clipped()
                }
            }
            .overlay(
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
            )
        }
    }
}

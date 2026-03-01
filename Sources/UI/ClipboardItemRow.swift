import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let folders: [AppFolder]
    let hoveredItemID: UUID?
    var selectedFolderID: UUID? = nil   // current view context
    var isHovered: Bool { hoveredItemID == item.id }
    
    var onPin: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onAssignToFolder: ((UUID?) -> Void)? = nil
    
    @State private var showFullText: Bool = false
    @State private var isPopoverHovered: Bool = false
    @State private var hideTask: DispatchWorkItem? = nil
    
    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "d"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("previewDelay") private var previewDelay: Double = 200
    @AppStorage("showSpecialSymbols") private var showSpecialSymbols: Bool = true
    
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
                if item.type == .image || (item.type == .file && isImageURL(item.fileURL)), 
                   let url = item.fileURL, let nsImage = NSImage(contentsOf: url) {
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .clipped()
                    
                    if item.type == .file {
                        Text(url.path)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                            .truncationMode(.middle)
                    }
                    
                } else if item.type == .file {
                    Text(item.fileURL?.lastPathComponent ?? "Unknown File")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    if let fileURL = item.fileURL {
                        Text(fileURL.path)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                            .truncationMode(.middle)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : (item.isPinned ? Color.accentColor.opacity(0.05) : Color.clear))
        )
        // Edge Popover for metadata & full text
        .popover(isPresented: $showFullText, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            popoverContent(for: item)
                .onHover { popoverHovered in
                    self.isPopoverHovered = popoverHovered
                    if !popoverHovered && !self.isHovered {
                        self.showFullText = false
                    }
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
                        if !self.isPopoverHovered {
                            self.showFullText = false
                        }
                    }
                    self.hideTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
                }
            }
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
                Text("Click to Paste")
                Text("⌥+Click to Paste Plain")
                Text("⌘+Click to Copy Only")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 2)
            
            Divider()
            
            // Content
            if item.type == .image || (item.type == .file && isImageURL(item.fileURL)), 
               let url = item.fileURL, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 400)
                    .padding()
            } else if item.type == .file {
                VStack(alignment: .leading) {
                    Text(item.fileURL?.lastPathComponent ?? "File")
                        .font(.headline)
                    Text(item.fileURL?.path ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
            } else {
                ScrollView {
                    Text(item.textContent ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
        .frame(width: 450, height: (item.type == .file || item.type == .image) ? nil : 500)
    }
    
    // Helpers
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
}

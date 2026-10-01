import Foundation

struct BackupDocument: Codable {
    struct ItemEntry: Codable {
        var item: ClipboardItem
        /// Cached media (files under SkyPaste/Images) as filename -> base64.
        var blobs: [String: String] = [:]
    }
    
    var format: String = "skypaste-backup"
    var version: Int = 1
    var exportedAt: Date = Date()
    var folders: [AppFolder] = []
    var folderShortcuts: [HotkeyManager.FolderShortcut] = []
    var folderMoveShortcuts: [HotkeyManager.FolderShortcut] = []
    var items: [ItemEntry] = []
    
    static let formatID = "skypaste-backup"
    /// Media files larger than this are skipped (metadata is still exported).
    static let maxBlobBytes = 10 * 1024 * 1024
}

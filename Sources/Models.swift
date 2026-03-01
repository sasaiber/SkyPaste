import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ItemType: String, Codable {
    case text
    case link
    case image
    case file
    case other
}

enum SortOption: String, Codable, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
}

struct AppFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "folder"
    var emoji: String? = "📁"
    var colorHex: String?
    
    var displayEmoji: String {
        emoji ?? "📁"
    }
    
    var displayColor: Color {
        if let hex = colorHex, let c = Color(hex: hex) {
            return c
        }
        return .accentColor
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var firstCopiedAt: Date
    let type: ItemType
    
    // For text / link
    var textContent: String?
    
    // For link
    var title: String?
    
    // For files / images
    var fileURL: URL?
    
    // In-memory properties (not saved directly to JSON, loaded lazily)
    var isPinned: Bool = false
    var pinnedOrder: Int = 0
    var folderID: UUID? = nil
    
    var sizeLabel: String?
    var appSource: String? // "Safari", "Xcode" (requires Accessibility)
    var appBundleID: String? // e.g. "com.apple.Safari"
    var copyCount: Int? = 1
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    func toHex() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}


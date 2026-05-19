import SwiftUI
import AppKit
import ServiceManagement

@available(macOS 13.0, *)
extension SMAppService {
    func registerSafe() {
        if self.status != .enabled {
            try? self.register()
        }
    }
    
    func unregisterSafe() {
        if self.status == .enabled {
            try? self.unregister()
        }
    }
}

// MARK: - Glass-like background with blur material
extension View {
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat = 16, style: RoundedCornerStyle = .continuous) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: style))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: style)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
    
    @ViewBuilder
    func glassListItem(isHovered: Bool, isPinned: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : (isPinned ? Color.accentColor.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isHovered ? .white.opacity(0.1) : .clear, lineWidth: 0.5)
            )
    }
}

// MARK: - Spring animations
extension Animation {
    static let smoothSpring = Animation.spring(duration: 0.35, bounce: 0.25, blendDuration: 0.15)
    static let quickSpring = Animation.spring(duration: 0.25, bounce: 0.2, blendDuration: 0.1)
    static let softSpring = Animation.spring(duration: 0.4, bounce: 0.3, blendDuration: 0.2)
}

// MARK: - Visual Effect View (for fallback backgrounds)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Time formatting
extension Date {
    func formattedTime(using format: String) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        if format == "ampm" {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.setLocalizedDateFormatFromTemplate("h:mm a")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        }
        return formatter.string(from: self)
    }
}

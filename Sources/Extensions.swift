import SwiftUI
import AppKit

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

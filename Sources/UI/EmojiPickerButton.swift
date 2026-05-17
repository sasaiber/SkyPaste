import SwiftUI
import AppKit

struct EmojiPickerButton: NSViewRepresentable {
    @Binding var emoji: String
    
    func makeNSView(context: Context) -> EmojiNSButton {
        let btn = EmojiNSButton()
        btn.title = emoji.isEmpty ? "📁" : emoji
        btn.font = .systemFont(ofSize: 20)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.12).cgColor
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.clicked)
        btn.onEmojiSelected = { e in
            DispatchQueue.main.async {
                self.emoji = e
            }
        }
        return btn
    }
    
    func updateNSView(_ nsView: EmojiNSButton, context: Context) {
        nsView.title = emoji.isEmpty ? "📁" : emoji
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        @objc func clicked(_ sender: EmojiNSButton) {
            AppDelegate.shared.isPickingEmoji = true
            sender.window?.makeFirstResponder(sender)
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

class EmojiNSButton: NSButton, NSTextInputClient {
    var onEmojiSelected: ((String) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        let str = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if let first = str.first(where: { $0.unicodeScalars.contains(where: { $0.properties.isEmoji }) }) {
            onEmojiSelected?(String(first))
            AppDelegate.shared.isPickingEmoji = false
            self.window?.makeFirstResponder(nil)
            
            // Try to force close the character palette by simulating Escape with a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let src = CGEventSource(stateID: .hidSystemState)
                let escapeDown = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)
                let escapeUp = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)
                escapeDown?.post(tap: .cghidEventTap)
                escapeUp?.post(tap: .cghidEventTap)
            }
        }
    }
    
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { return NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { return NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { return false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { return nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { return [] }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { return .zero }
    func characterIndex(for point: NSPoint) -> Int { return NSNotFound }
}

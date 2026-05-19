import SwiftUI
import AppKit

struct EmojiPickerButton: NSViewRepresentable {
    @Binding var emoji: String
    
    func makeNSView(context: Context) -> EmojiNSButton {
        let btn = EmojiNSButton()
        btn.title = emoji.isEmpty ? "📁" : emoji
        btn.font = .systemFont(ofSize: 14)
        btn.setButtonType(.momentaryPushIn)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.focusRingType = .none
        btn.alignment = .center
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        btn.layer?.borderColor = NSColor.separatorColor.cgColor
        btn.layer?.borderWidth = 1
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
            sender.window?.makeFirstResponder(sender)
            NSApp.orderFrontCharacterPalette(sender)
        }
    }
}

class EmojiNSButton: NSButton, NSTextInputClient {
    var onEmojiSelected: ((String) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        let str = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if !str.isEmpty {
            onEmojiSelected?(str)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeFirstResponder(nil)
                
                // Try to force close the character palette by simulating Escape
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
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window else { return .zero }
        let rectInWindow = self.convert(self.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        return screenRect
    }
    func characterIndex(for point: NSPoint) -> Int { return NSNotFound }
}

class FixedColorWell: NSColorWell {
    var customWidth: CGFloat = 28
    var customHeight: CGFloat = 28
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: customWidth, height: customHeight)
    }
}

struct NativeColorPicker: NSViewRepresentable {
    @Binding var color: Color
    var width: CGFloat = 28
    var height: CGFloat = 28
    
    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = FixedColorWell()
        colorWell.customWidth = width
        colorWell.customHeight = height
        colorWell.color = NSColor(color)
        if #available(macOS 13.0, *) {
            colorWell.colorWellStyle = .minimal
        }
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }
    
    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = NSColor(color)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: NativeColorPicker
        
        init(_ parent: NativeColorPicker) {
            self.parent = parent
        }
        
        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = Color(sender.color)
        }
    }
}

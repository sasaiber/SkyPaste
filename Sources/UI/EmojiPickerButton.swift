import SwiftUI
import AppKit

// MARK: - Emoji Picker Button (system Character Palette)

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
        btn.action = #selector(Coordinator.clicked(_:))
        btn.onEmojiSelected = { e in
            DispatchQueue.main.async {
                context.coordinator.updateEmoji(e)
            }
        }
        return btn
    }

    func updateNSView(_ nsView: EmojiNSButton, context: Context) {
        nsView.title = emoji.isEmpty ? "📁" : emoji
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: EmojiPickerButton

        init(_ parent: EmojiPickerButton) { self.parent = parent }

        func updateEmoji(_ e: String) { parent.emoji = e }

        @objc func clicked(_ sender: EmojiNSButton) {
            // 1. Activate the app so our window can become key
            NSApp.activate(ignoringOtherApps: true)

            // 2. Make our panel the key window
            sender.window?.makeKeyAndOrderFront(nil)

            // 3. Make the button first responder so the input context
            //    is wired up before we open the palette
            sender.window?.makeFirstResponder(sender)

            // 4. Open the palette on the next run-loop tick — by then
            //    the window IS the key window and the button IS first
            //    responder, so the palette opens instantly, every time.
            DispatchQueue.main.async {
                NSApp.orderFrontCharacterPalette(sender)
            }
        }
    }
}

// MARK: - EmojiNSButton (NSTextInputClient receiver)

class EmojiNSButton: NSButton, NSTextInputClient {
    var onEmojiSelected: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    // Lazily created so the context is only allocated when needed
    private lazy var _inputContext = NSTextInputContext(client: self)
    override var inputContext: NSTextInputContext? { _inputContext }

    // Called by the system when the user picks an emoji
    func insertText(_ string: Any, replacementRange: NSRange) {
        let str = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        guard !str.isEmpty else { return }
        onEmojiSelected?(str)
        // Resign first responder — palette closes naturally on its own
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    // --- Minimal NSTextInputClient stubs ---
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange()  -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    // Position hint so the palette appears near the button
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window else { return .zero }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}

// MARK: - Color Well

class FixedColorWell: NSColorWell {
    var customWidth:  CGFloat = 28
    var customHeight: CGFloat = 28
    override var intrinsicContentSize: NSSize {
        NSSize(width: customWidth, height: customHeight)
    }
}

struct NativeColorPicker: NSViewRepresentable {
    @Binding var color: Color
    var width:  CGFloat = 28
    var height: CGFloat = 28

    func makeNSView(context: Context) -> NSColorWell {
        let cw = FixedColorWell()
        cw.customWidth  = width
        cw.customHeight = height
        cw.color = NSColor(color)
        if #available(macOS 13.0, *) { cw.colorWellStyle = .minimal }
        cw.target = context.coordinator
        cw.action = #selector(Coordinator.colorChanged(_:))
        return cw
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        nsView.color = NSColor(color)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: NativeColorPicker
        init(_ parent: NativeColorPicker) { self.parent = parent }
        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = Color(sender.color)
        }
    }
}

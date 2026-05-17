import SwiftUI

struct ShortcutRecorder: View {
    var actionName: String = ""
    @Binding var keyString: String
    @Binding var modifiers: Int
    var onValidate: ((String, Int, String) -> String?)? = nil
    
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                isRecording.toggle()
                if isRecording { 
                    self.errorMessage = nil
                    startRecording() 
                } else { stopRecording() }
            }) {
                Text(isRecording ? "Listening..." : formatShortcut())
                    .frame(width: 100)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : (errorMessage != nil ? .red : .secondary))
            .onDisappear { stopRecording() }
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private let keyCodeToString: [UInt16: String] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
        0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
        0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
        0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
        0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
        0x06: "z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
        0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x21: "[", 0x1E: "]", 0x2A: "\\", 0x29: ";", 0x27: "'",
        0x2B: ",", 0x2F: ".", 0x32: "`", 0x1B: "-", 0x18: "=",
        0x33: "delete", 0x75: "forwarddelete", 0x31: "space",
        0x24: "return", 0x77: "tab", 0x35: "escape",
        0x7E: "up", 0x7D: "down", 0x7B: "left", 0x7C: "right",
        0x4C: "enter",
        0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
        0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
        0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12"
    ]
    
    private func formatShortcut() -> String {
        guard !keyString.isEmpty else { return "None" }
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        
        let specialKeys: [String: String] = [
            "delete": "⌫", "forwarddelete": "⌦", "space": "␣",
            "return": "↩", "enter": "⌅", "escape": "⎋",
            "up": "↑", "down": "↓", "left": "←", "right": "→"
        ]
        
        let mapped = specialKeys[keyString.lowercased()] ?? keyString.uppercased()
        result += mapped
        return result
    }
    
    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            guard let char = keyCodeToString[event.keyCode] else { return event }
            
            if let err = onValidate?(char, Int(flags.rawValue), actionName) {
                self.errorMessage = err
                self.isRecording = false
                self.stopRecording()
                return nil
            }
            
            self.keyString = char
            self.modifiers = Int(flags.rawValue)
            self.isRecording = false
            self.stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

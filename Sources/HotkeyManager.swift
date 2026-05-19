import AppKit
import Carbon
import os

class WindowManager {
    static let shared = WindowManager()
    var panel: FloatingPanel?
    
    func show(contentView: NSView, size: NSSize, at position: String = "cursor", button: NSStatusBarButton? = nil) {
        if panel == nil {
            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                contentView: contentView,
                statusBarButton: button,
                position: position
            )
            self.panel = panel
        } else {
            panel?.contentView = contentView
            if let p = panel {
                p.position = position
                p.statusBarButton = button
                let origin: NSPoint
                if p.isPresented {
                    origin = p.computeResizedOrigin(newSize: size)
                } else {
                    origin = p.computeOrigin(size: size, position: position, button: button)
                    p.saveInitialAnchors(origin: origin, size: size)
                }
                p.setFrame(NSRect(origin: origin, size: size), display: true)
            }
        }
        
        guard let panel = panel else { return }
        
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.isPresented = true
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NSNotification.Name("SkyPasteWindowDidShow"), object: nil)
    }
    
    func close() {
        panel?.close()
        // Do not set panel = nil to reuse it
    }
    
    var isWindowVisible: Bool {
        panel?.isPresented ?? false
    }
    
    func contains(_ point: NSPoint) -> Bool {
        return panel?.frame.contains(point) ?? false
    }
}

// MARK: - FloatingPanel (Maccy-style)
class FloatingPanel: NSPanel, NSWindowDelegate {
    enum VerticalAnchor {
        case top
        case bottom
        case center
    }
    
    var isPresented: Bool = false
    var position: String
    var statusBarButton: NSStatusBarButton?
    var anchorPoint: NSPoint?
    var verticalAnchor: VerticalAnchor = .top
    var initialTopY: CGFloat? = nil
    var initialBottomY: CGFloat? = nil
    var initialCenterY: CGFloat? = nil
    private let onClose: () -> Void
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    func saveInitialAnchors(origin: NSPoint, size: NSSize) {
        if verticalAnchor == .top {
            initialTopY = origin.y + size.height
        } else if verticalAnchor == .bottom {
            initialBottomY = origin.y
        } else if verticalAnchor == .center {
            initialCenterY = origin.y + size.height / 2
        }
    }
    
    init(
        contentRect: NSRect,
        contentView: NSView,
        statusBarButton: NSStatusBarButton?,
        position: String
    ) {
        self.statusBarButton = statusBarButton
        self.position = position
        self.onClose = {}
        
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        delegate = self
        
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        hasShadow = true
        titlebarSeparatorStyle = .none
        
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        
        self.contentView = contentView
        
        // Position
        let origin = computeOrigin(size: contentRect.size, position: position, button: statusBarButton)
        saveInitialAnchors(origin: origin, size: contentRect.size)
        setFrameOrigin(origin)
    }
    
    func computeOrigin(size: NSSize, position: String, button: NSStatusBarButton?) -> NSPoint {
        switch position {
        case "statusItem":
            verticalAnchor = .top
            if let button = button, let window = button.window {
                let rectInWindow = button.convert(button.bounds, to: nil)
                let screenRect = window.convertToScreen(rectInWindow)
                
                // If the screenRect is completely broken (e.g. 0,0), fallback
                if screenRect.minY > 0 {
                    let originX = screenRect.midX - (size.width / 2)
                    let screen = NSScreen.screens.first(where: { $0.frame.contains(screenRect.origin) }) ?? NSScreen.main ?? NSScreen.screens.first
                    
                    // Align strictly below the status bar button bottom
                    var origin = NSPoint(x: originX, y: screenRect.minY - size.height - 1)
                    
                    if let screen = screen {
                        // Clamp window top so it is strictly below the menu bar bottom (visibleFrame.maxY)
                        let maxTop = screen.visibleFrame.maxY
                        if origin.y + size.height > maxTop {
                            origin.y = maxTop - size.height
                            verticalAnchor = .top
                        }
                        
                        if origin.x + size.width > screen.visibleFrame.maxX {
                            origin.x = screen.visibleFrame.maxX - size.width
                        } else if origin.x < screen.visibleFrame.minX {
                            origin.x = screen.visibleFrame.minX
                        }
                    }
                    return origin
                }
            }
            fallthrough
        case "center":
            verticalAnchor = .center
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let frame = screen.visibleFrame
                let x = frame.midX - size.width / 2
                let y = frame.midY - size.height / 2
                return NSPoint(x: x, y: y)
            }
            fallthrough
        default:
            let mouseLocation: NSPoint
            if let savedAnchor = anchorPoint {
                mouseLocation = savedAnchor
            } else {
                mouseLocation = NSEvent.mouseLocation
                anchorPoint = mouseLocation
            }
            var point = mouseLocation
            point.x += 10
            
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
                // Determine whether to place the window above or below the cursor.
                // We prefer below the cursor, but if there isn't enough space, we place it above.
                let spaceBelow = mouseLocation.y - screen.visibleFrame.minY
                if spaceBelow < size.height + 10 {
                    // Place it above the cursor (with 15 points spacing to clear the cursor itself)
                    point.y = mouseLocation.y + 15
                    verticalAnchor = .bottom
                } else {
                    // Place it below the cursor
                    point.y = mouseLocation.y - size.height - 10
                    verticalAnchor = .top
                }
                
                // Clamp X to visible screen bounds
                if point.x + size.width > screen.visibleFrame.maxX {
                    point.x = screen.visibleFrame.maxX - size.width
                }
                if point.x < screen.visibleFrame.minX {
                    point.x = screen.visibleFrame.minX
                }
                
                // Clamp Y to visible screen bounds
                if point.y < screen.visibleFrame.minY {
                    point.y = screen.visibleFrame.minY
                    verticalAnchor = .bottom // Resting on bottom edge, so anchor bottom
                }
                if point.y + size.height > screen.visibleFrame.maxY {
                    point.y = screen.visibleFrame.maxY - size.height
                    verticalAnchor = .top // Resting on top edge, so anchor top
                }
            } else {
                // Fallback in case screen is nil
                point.y -= (size.height + 10)
                verticalAnchor = .top
            }
            return point
        }
    }
    
    func computeResizedOrigin(newSize: NSSize) -> NSPoint {
        var newOrigin = self.frame.origin
        
        if position == "center" {
            if let centerY = initialCenterY {
                newOrigin.y = centerY - newSize.height / 2
            } else {
                newOrigin.y = self.frame.midY - newSize.height / 2
            }
            newOrigin.x = self.frame.midX - newSize.width / 2
            return newOrigin
        }
        
        switch verticalAnchor {
        case .top:
            if let topY = initialTopY {
                newOrigin.y = topY - newSize.height
            } else {
                newOrigin.y = self.frame.maxY - newSize.height
            }
        case .bottom:
            if let bottomY = initialBottomY {
                newOrigin.y = bottomY
            }
        case .center:
            if let centerY = initialCenterY {
                newOrigin.y = centerY - newSize.height / 2
            } else {
                newOrigin.y = self.frame.midY - newSize.height / 2
            }
        }
        
        return newOrigin
    }
    
    func verticallyResize(to newHeight: CGFloat, animate: Bool = true) {
        var newSize = frame.size
        newSize.height = newHeight
        
        let newOrigin = computeResizedOrigin(newSize: newSize)
        let targetFrame = NSRect(origin: newOrigin, size: newSize)
        
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true)
        }
    }

    
    override func resignKey() {
        super.resignKey()
        // Removed close() so that picking emoji or colors doesn't kill the popup
    }
    
    override func close() {
        super.close()
        isPresented = false
        anchorPoint = nil
        initialTopY = nil
        initialBottomY = nil
        initialCenterY = nil
        statusBarButton?.isHighlighted = false
        onClose()
    }
    
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// MARK: - Carbon-based Global Hotkey (Maccy-style)
// Uses RegisterEventHotKey — same approach as KeyboardShortcuts library

// Complete keycode-to-key-string mapping (based on Sauce library)
// https://github.com/p0deje/Maccy/blob/master/Maccy/Extensions/Sauce+Key.swift
private let keyCodeToKeyString: [UInt16: String] = [
    // ANSI Letters (QWERTY layout)
    0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
    0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
    0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
    0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
    0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
    0x06: "z",
    // Digits
    0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
    0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
    // Symbols (ANSI layout)
    0x21: "[", 0x1E: "]", 0x2A: "\\",
    0x29: ";", 0x27: "'", 0x2B: ",",
    0x2F: ".", 0x2C: "/", 0x32: "`",
    0x1B: "-", 0x18: "=",
    // Special keys
    0x33: "delete",
    0x75: "forwarddelete",
    0x31: "space",
    0x24: "return",
    0x77: "tab",
    0x35: "escape",
    0x7E: "up",
    0x7D: "down",
    0x7B: "left",
    0x7C: "right",
    0x4C: "enter",
    // Function keys
    0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
    0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
    0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12",
    0x69: "f13", 0x6B: "f14", 0x71: "f15", 0x6A: "f16",
    0x40: "f17", 0x4F: "f18", 0x50: "f19", 0x5A: "f20",
    // Keypad
    0x52: "keypad0", 0x53: "keypad1", 0x54: "keypad2",
    0x55: "keypad3", 0x56: "keypad4", 0x57: "keypad5",
    0x58: "keypad6", 0x59: "keypad7", 0x5B: "keypad8",
    0x5C: "keypad9", 0x47: "keypadDecimal",
    0x43: "keypadMultiply", 0x4E: "keypadMinus", 0x4B: "keypadDivide",
    0x45: "keypadEquals", 0x51: "keypadClear",
]

// Reverse mapping: key string -> keycode (for Carbon registration)
private let keyStringToKeyCode: [String: UInt16] = {
    var result: [String: UInt16] = [:]
    for (code, key) in keyCodeToKeyString {
        result[key] = code
    }
    return result
}()

// Human-readable display names for special keys
let specialKeyDisplayNames: [String: String] = [
    "delete": "⌫",
    "forwarddelete": "⌦",
    "space": "␣",
    "return": "↩",
    "enter": "↩",
    "escape": "⎋",
    "tab": "⇥",
    "up": "↑",
    "down": "↓",
    "left": "←",
    "right": "→",
    "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
    "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
    "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
    "f13": "F13", "f14": "F14", "f15": "F15", "f16": "F16",
    "f17": "F17", "f18": "F18", "f19": "F19", "f20": "F20",
    "keypad0": "⌨0", "keypad1": "⌨1", "keypad2": "⌨2",
    "keypad3": "⌨3", "keypad4": "⌨4", "keypad5": "⌨5",
    "keypad6": "⌨6", "keypad7": "⌨7", "keypad8": "⌨8",
    "keypad9": "⌨9",
]

// Converts NSEvent.ModifierFlags to Carbon modifier mask
private func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if nsFlags.contains(.command)  { carbon |= UInt32(cmdKey) }
    if nsFlags.contains(.option)   { carbon |= UInt32(optionKey) }
    if nsFlags.contains(.control)  { carbon |= UInt32(controlKey) }
    if nsFlags.contains(.shift)    { carbon |= UInt32(shiftKey) }
    if carbon == 0 { carbon |= UInt32(cmdKey) }
    return carbon
}

class HotkeyManager {
    static let shared = HotkeyManager()
    var onToggleRequested: (() -> Void)?
    var onPastePlainRequested: (() -> Void)?
    var onLibraryRequested: (() -> Void)?
    var onFolderShortcutRequested: ((UUID) -> Void)?
    var onFolderMoveRequested: ((UUID) -> Void)?
    
    struct FolderShortcut: Codable {
        let folderID: UUID
        let keyText: String
        let modifiers: Int
    }
    
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var hotKeyActions: [UInt32: () -> Void] = [:]
    private let actionsLock = NSLock()
    private var nextHotKeyID: UInt32 = 1
    
    func start() {
        unregisterAll()
        
        let defaults = UserDefaults.standard
        
        // --- Hotkey 1: Show/Toggle Popover ---
        let hk1Key = (defaults.string(forKey: "hk1Key") ?? "s").lowercased()
        var hk1Modifiers = defaults.integer(forKey: "hk1Modifiers")
        if hk1Modifiers == 0 {
            hk1Modifiers = Int(NSEvent.ModifierFlags.command.rawValue)
        }
        let flags1 = NSEvent.ModifierFlags(rawValue: UInt(hk1Modifiers))
        registerCarbonHotKey(key: hk1Key, modifiers: flags1) { [weak self] in
            self?.onToggleRequested?()
        }
        
        // --- Hotkey 2: Paste Plain Text ---
        let hk2Key = (defaults.string(forKey: "hk2Key") ?? "v").lowercased()
        var hk2Modifiers = defaults.integer(forKey: "hk2Modifiers")
        if hk2Modifiers == 0 {
            hk2Modifiers = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue)
        }
        let flags2 = NSEvent.ModifierFlags(rawValue: UInt(hk2Modifiers))
        registerCarbonHotKey(key: hk2Key, modifiers: flags2) { [weak self] in
            self?.onPastePlainRequested?()
        }
        
        // --- Hotkey 3: Library ---
        let hkLibKey = (defaults.string(forKey: "hkLibraryKey") ?? "a").lowercased()
        var hkLibModifiers = defaults.integer(forKey: "hkLibraryModifiers")
        if hkLibModifiers == 0 {
            hkLibModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
        }
        let flagsLib = NSEvent.ModifierFlags(rawValue: UInt(hkLibModifiers))
        registerCarbonHotKey(key: hkLibKey, modifiers: flagsLib) { [weak self] in
            self?.onLibraryRequested?()
        }
        
        // --- Folder Open Shortcuts ---
        if let data = defaults.data(forKey: "folderShortcuts"),
           let shortcuts = try? JSONDecoder().decode([FolderShortcut].self, from: data) {
            for sc in shortcuts {
                let scFlags = NSEvent.ModifierFlags(rawValue: UInt(sc.modifiers))
                let folderID = sc.folderID
                registerCarbonHotKey(key: sc.keyText.lowercased(), modifiers: scFlags) { [weak self] in
                    self?.onFolderShortcutRequested?(folderID)
                }
            }
        }
        
        // --- Folder Move Shortcuts ---
        if let data = defaults.data(forKey: "folderMoveShortcuts"),
           let shortcuts = try? JSONDecoder().decode([FolderShortcut].self, from: data) {
            for sc in shortcuts {
                let scFlags = NSEvent.ModifierFlags(rawValue: UInt(sc.modifiers))
                let folderID = sc.folderID
                registerCarbonHotKey(key: sc.keyText.lowercased(), modifiers: scFlags) { [weak self] in
                    self?.onFolderMoveRequested?(folderID)
                }
            }
        }
        
        installCarbonHandler()
    }
    
    // MARK: - Carbon Registration
    
    private func registerCarbonHotKey(key: String, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let normalizedKey = key.lowercased()
        guard let keyCode = keyStringToKeyCode[normalizedKey] else {
            os_log(.error, "SkyPaste HotkeyManager: Unknown key '%{public}@'", normalizedKey)
            return
        }
        let carbonMods = carbonModifiers(from: modifiers)
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x534B5950),
                                      id: nextHotKeyID)
        actionsLock.lock()
        hotKeyActions[nextHotKeyID] = action
        actionsLock.unlock()
        nextHotKeyID += 1
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                                          GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
        } else {
            os_log(.error, "SkyPaste HotkeyManager: Failed to register key='%{public}@' mods=%{public}u status=%{public}d", normalizedKey, carbonMods, status)
        }
    }
    
    private func installCarbonHandler() {
        if handlerRef != nil { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        let callbackPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let carbonCallback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { (_, event, userData) in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            
            mgr.actionsLock.lock()
            let action = mgr.hotKeyActions[hotKeyID.id]
            mgr.actionsLock.unlock()
            
            if let action = action {
                DispatchQueue.main.async { action() }
            }
            
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), carbonCallback, 1, &eventType, callbackPtr, &handlerRef)
    }
    
    private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        actionsLock.lock()
        hotKeyActions.removeAll()
        actionsLock.unlock()
        nextHotKeyID = 1
        
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }
    
    func stop() {
        unregisterAll()
    }
}

import AppKit
import Carbon

class WindowManager {
    static let shared = WindowManager()
    
    func showPopoverAtCursor(popover: NSPopover) {
        guard !popover.isShown else {
            popover.performClose(nil)
            return
        }
        
        let targetLocation = NSEvent.mouseLocation
        let pointRect = NSRect(x: targetLocation.x, y: targetLocation.y, width: 1, height: 1)
        
        let dummyWindow = NSWindow(contentRect: pointRect,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        dummyWindow.backgroundColor = .clear
        dummyWindow.isOpaque = false
        dummyWindow.hasShadow = false
        dummyWindow.level = .floating
        dummyWindow.makeKeyAndOrderFront(nil)
        
        if let view = dummyWindow.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
        
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { _ in
            dummyWindow.close()
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showPopoverAtCenter(popover: NSPopover) {
        guard !popover.isShown else {
            popover.performClose(nil)
            return
        }
        
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            showPopoverAtCursor(popover: popover)
            return
        }
        
        let screenFrame = screen.visibleFrame
        let centerX = screenFrame.midX
        let centerY = screenFrame.midY
        let pointRect = NSRect(x: centerX, y: centerY, width: 1, height: 1)
        
        let dummyWindow = NSWindow(contentRect: pointRect,
                                   styleMask: .borderless,
                                   backing: .buffered,
                                   defer: false)
        dummyWindow.backgroundColor = .clear
        dummyWindow.isOpaque = false
        dummyWindow.hasShadow = false
        dummyWindow.level = .floating
        dummyWindow.makeKeyAndOrderFront(nil)
        
        if let view = dummyWindow.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
        
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { _ in
            dummyWindow.close()
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Carbon-based Global Hotkey (same approach as Maccy / KeyboardShortcuts library)

// Maps a character string to a Carbon virtual keyCode
private let carbonKeyMap: [String: UInt32] = [
    "a": UInt32(kVK_ANSI_A), "s": UInt32(kVK_ANSI_S), "d": UInt32(kVK_ANSI_D),
    "f": UInt32(kVK_ANSI_F), "h": UInt32(kVK_ANSI_H), "g": UInt32(kVK_ANSI_G),
    "z": UInt32(kVK_ANSI_Z), "x": UInt32(kVK_ANSI_X), "c": UInt32(kVK_ANSI_C),
    "v": UInt32(kVK_ANSI_V), "b": UInt32(kVK_ANSI_B), "q": UInt32(kVK_ANSI_Q),
    "w": UInt32(kVK_ANSI_W), "e": UInt32(kVK_ANSI_E), "r": UInt32(kVK_ANSI_R),
    "t": UInt32(kVK_ANSI_T), "y": UInt32(kVK_ANSI_Y), "u": UInt32(kVK_ANSI_U),
    "i": UInt32(kVK_ANSI_I), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
    "l": UInt32(kVK_ANSI_L), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K),
    "n": UInt32(kVK_ANSI_N), "m": UInt32(kVK_ANSI_M),
    "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
    "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
    "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
    "9": UInt32(kVK_ANSI_9),
]

// Converts NSEvent.ModifierFlags to Carbon modifier mask
private func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if nsFlags.contains(.command) { carbon |= UInt32(cmdKey) }
    if nsFlags.contains(.option)  { carbon |= UInt32(optionKey) }
    if nsFlags.contains(.control) { carbon |= UInt32(controlKey) }
    if nsFlags.contains(.shift)   { carbon |= UInt32(shiftKey) }
    return carbon
}

class HotkeyManager {
    static let shared = HotkeyManager()
    var onToggleRequested: (() -> Void)?
    var onPastePlainRequested: (() -> Void)?
    var onFolderShortcutRequested: ((UUID) -> Void)?
    
    struct FolderShortcut: Codable {
        let folderID: UUID
        let keyText: String
        let modifiers: Int
    }
    
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    
    // Each registered hotkey gets a unique ID; we map ID -> action
    private var hotKeyActions: [UInt32: () -> Void] = [:]
    private var nextHotKeyID: UInt32 = 1
    
    func start() {
        unregisterAll()
        
        let defaults = UserDefaults.standard
        
        // --- Hotkey 1: Show/Toggle Popover ---
        let hk1Key = (defaults.string(forKey: "hk1Key") ?? "v").lowercased()
        let hk1ModInt = defaults.integer(forKey: "hk1Modifiers")
        let raw1 = hk1ModInt == 0
            ? (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
            : UInt(hk1ModInt)
        let flags1 = NSEvent.ModifierFlags(rawValue: raw1)
        
        registerCarbonHotKey(key: hk1Key, modifiers: flags1) { [weak self] in
            self?.onToggleRequested?()
        }
        
        // --- Hotkey 2: Paste Plain Text ---
        let hk2Key = (defaults.string(forKey: "hk2Key") ?? "v").lowercased()
        let hk2ModInt = defaults.integer(forKey: "hk2Modifiers")
        let raw2 = hk2ModInt == 0
            ? (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue)
            : UInt(hk2ModInt)
        let flags2 = NSEvent.ModifierFlags(rawValue: raw2)
        
        registerCarbonHotKey(key: hk2Key, modifiers: flags2) { [weak self] in
            self?.onPastePlainRequested?()
        }
        
        // --- Folder Shortcuts ---
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
        
        installCarbonHandler()
    }
    
    // MARK: - Carbon Registration
    
    private func registerCarbonHotKey(key: String, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        guard let keyCode = carbonKeyMap[key] else { return }
        let carbonMods = carbonModifiers(from: modifiers)
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x534B5950), // "SKYP"
                                      id: nextHotKeyID)
        hotKeyActions[nextHotKeyID] = action
        nextHotKeyID += 1
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotKeyID,
                                          GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }
    
    private func installCarbonHandler() {
        if handlerRef != nil { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        
        let callbackPtr = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
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
            
            if let action = mgr.hotKeyActions[hotKeyID.id] {
                DispatchQueue.main.async { action() }
            }
            
            return noErr
        }, 1, &eventType, callbackPtr, &handlerRef)
    }
    
    private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        hotKeyActions.removeAll()
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

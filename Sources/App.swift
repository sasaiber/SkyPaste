import SwiftUI
import AppKit

@main
struct SkyPasteApp: App {
    @StateObject private var storage = Storage()
    @StateObject private var monitor: ClipboardMonitor
    
    // We use a custom window manager for the HUD
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        let store = Storage()
        _storage = StateObject(wrappedValue: store)
        _monitor = StateObject(wrappedValue: ClipboardMonitor(storage: store))
    }

    var body: some Scene {
        // Dummy scene to satisfy SwiftUI
        Settings {
            Text("Settings")
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self else { return }
                self.popover.performClose(nil)
            }
        }
    }
    
    func popoverWillClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        
        // Important: Clear the content view controller to break retain cycles
        // when popover closes. This prevents memory leaks.
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController = nil
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    var globalStore: Storage!
    
    var popover: NSPopover!
    var statusBarItem: NSStatusItem!
    var outsideClickMonitor: Any?
    
    // Global state passed from SkyPasteApp
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Set activation policy
        NSApp.setActivationPolicy(.accessory)
        
        self.globalStore = Storage()
        
        // Create popover FIRST and set delegate
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover
        
        // THEN create the view controller after delegate is set
        let mainView = MainView(storage: self.globalStore)
        popover.contentViewController = NSHostingController(rootView: mainView)
        
        // Create Status Bar Item
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "SkyPaste")
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SkyPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        self.statusBarItem.menu = menu
        
        if self.statusBarItem.button != nil {
            self.statusBarItem.menu = nil // We keep the hack for left-click triggering the popover
        }
        
        // Show Welcome Guide if permissions missing
        if !AXIsProcessTrusted() && !UserDefaults.standard.bool(forKey: "hasDismissedWelcome") {
            showWelcomeWindow()
        }
        
        // Register Hotkeys
        HotkeyManager.shared.onToggleRequested = { [weak self] in
            guard let self = self else { return }
            self.togglePopover(nil)
        }
        HotkeyManager.shared.onPastePlainRequested = { [weak self] in
            guard let monitor = self?.monitorRef else { return }
            let pb = NSPasteboard.general
            if let string = pb.string(forType: .string) {
                pb.clearContents()
                pb.setString(string, forType: .string)
                monitor.triggerCmdV()
            }
        }
        HotkeyManager.shared.onFolderShortcutRequested = { [weak self] folderID in
            guard let self = self else { return }
            self.monitorRef?.storage.selectedFolderID = folderID
            self.togglePopover(nil)
        }
        HotkeyManager.shared.start()
        
        // Start monitoring clipboard
        let monitor = ClipboardMonitor(storage: self.globalStore)
        monitor.start()
        // We need to keep a strong reference, usually we'd pass it down or store it
        self.monitorRef = monitor
    }
    
    var monitorRef: ClipboardMonitor?
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if self.popover.isShown {
            self.popover.performClose(sender)
        } else {
            // Recreate the content view controller if it was cleared
            if self.popover.contentViewController == nil {
                let mainView = MainView(storage: self.globalStore)
                self.popover.contentViewController = NSHostingController(rootView: mainView)
            }
            
            let position = UserDefaults.standard.string(forKey: "popupPosition") ?? "cursor"
            switch position {
            case "statusItem":
                if let button = self.statusBarItem.button {
                    // Create a dummy window at button location for proper positioning
                    let buttonFrame = button.window?.convertToScreen(button.frame) ?? button.frame
                    let dummyWindow = NSWindow(contentRect: buttonFrame,
                                               styleMask: .borderless,
                                               backing: .buffered,
                                               defer: false)
                    dummyWindow.backgroundColor = .clear
                    dummyWindow.isOpaque = false
                    dummyWindow.hasShadow = false
                    dummyWindow.level = .floating
                    dummyWindow.makeKeyAndOrderFront(nil)
                    
                    if let view = dummyWindow.contentView {
                        self.popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
                    }
                    
                    // Keep window alive while popover is shown
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        if let self = self, !self.popover.isShown {
                            dummyWindow.close()
                        }
                    }
                } else {
                    WindowManager.shared.showPopoverAtCursor(popover: popover)
                }
            case "center":
                WindowManager.shared.showPopoverAtCenter(popover: popover)
            default: // "cursor"
                WindowManager.shared.showPopoverAtCursor(popover: popover)
            }
            NSApp.activate(ignoringOtherApps: true)
            self.popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    var settingsWindow: NSWindow?
    
    @MainActor
    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let preferencesView = PreferencesView(storage: self.globalStore)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "SkyPaste Settings"
        window.contentViewController = NSHostingController(rootView: preferencesView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.settingsWindow = window
    }
    
    var welcomeWindow: NSWindow?
    
    @MainActor
    func showWelcomeWindow() {
        if let window = welcomeWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let welcomeView = WelcomeView(onContinue: { [weak self] in
            DispatchQueue.main.async {
                self?.welcomeWindow?.orderOut(nil)
                self?.welcomeWindow = nil
                self?.togglePopover(nil)
            }
        })
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 450),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.contentViewController = NSHostingController(rootView: welcomeView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.welcomeWindow = window
    }
    
    // MARK: - Application Termination
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop clipboard monitoring
        monitorRef?.stop()
        
        // Stop hotkey manager
        HotkeyManager.shared.stop()
        
        // Clear image cache
        ImageCache.shared.clear()
        
        // Clean up windows
        popover = nil
        settingsWindow = nil
        welcomeWindow = nil
        
        // Remove global monitor
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // macOS menu-bar app, don't terminate when window closes
    }
}

